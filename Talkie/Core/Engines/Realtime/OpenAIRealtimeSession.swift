import Foundation

/// What the coordinator needs from a live session — kept tiny so tests can fake it.
protocol LiveDictationSession: Sendable {
    func feed(_ samples: [Float]) async
    func finish() async throws -> Transcript
    func cancel() async
}

/// Receives the cumulative partial transcript as it streams in. Synchronous and
/// non-isolated — the receive loop must never await UI work, so the sink just
/// hands the latest full string to a lock-box the coordinator pumps to the UI.
typealias PartialTranscriptSink = @Sendable (String) -> Void

/// One live Realtime transcription session: begin → feed (many) → finish | cancel.
/// Deltas accumulate as they arrive; finish() commits the buffer and waits for the
/// completed transcript. Errors surface on finish()/begin() — the coordinator
/// falls back to the batch engine with the full recording.
actor OpenAIRealtimeSession {
    private let transport: RealtimeTransport
    private let model: String
    private let vocabulary: String?
    private let language: String?
    private let encoder: RealtimePCMEncoder

    private let onPartial: PartialTranscriptSink?
    private var receiveLoop: Task<Void, Never>?
    /// Authoritative transcripts of VAD-committed segments, in arrival order. The
    /// returned transcript is these joined; cleaner than concatenated deltas.
    private var finalSegments: [String] = []
    /// Deltas of the segment currently being transcribed (cleared on its completed).
    private var currentSegmentDeltas = ""
    /// Committed-but-not-yet-completed segments. finish() waits for this to hit 0.
    private var openItems = 0
    /// finish() was called — fn released; we're draining the trailing segment.
    private var finishing = false
    /// The trailing finish() commit was acknowledged (a `committed` for it, or an
    /// empty-commit). Gates finalization so an in-flight segment completing first
    /// doesn't end the session before the trailing segment arrives.
    private var finalCommitSeen = false
    private var completedTranscript: String?
    private var serverError: String?
    private var finishContinuation: CheckedContinuation<String, Error>?

    /// Cumulative live text for the partial sink: finalized segments + the
    /// in-progress segment's deltas, spaced without doubling.
    private func liveCumulative() -> String {
        let base = finalSegments.joined(separator: " ")
        if currentSegmentDeltas.isEmpty { return base }
        if base.isEmpty { return currentSegmentDeltas }
        return currentSegmentDeltas.hasPrefix(" ") ? base + currentSegmentDeltas : base + " " + currentSegmentDeltas
    }

    init(transport: RealtimeTransport, model: String, vocabulary: String?, language: String?,
         encoder: RealtimePCMEncoder, onPartial: PartialTranscriptSink? = nil) {
        self.transport = transport
        self.model = model
        self.vocabulary = vocabulary
        self.language = language
        self.encoder = encoder
        self.onPartial = onPartial
    }

    func begin() async throws {
        try await transport.connect()
        try await transport.send(RealtimeClientEvent.sessionUpdate(model: model, vocabulary: vocabulary, language: language).encoded())
        receiveLoop = Task { await self.runReceiveLoop() }
    }

    func feed(_ samples: [Float]) async {
        guard serverError == nil, completedTranscript == nil else { return }
        guard let pcm = try? encoder.encode(samples), !pcm.isEmpty else { return }
        try? await transport.send(RealtimeClientEvent.audioAppend(pcm16: pcm).encoded())
    }

    func finish() async throws -> Transcript {
        // EVERY exit — early server-error throw, a failed send, or a continuation
        // resumed with an error — must close the socket and stop the receive loop,
        // or the batch-fallback path orphans a live WebSocket (Task 7's "no orphaned
        // socket" check). The continuation resumes before the defer fires; cleanup()
        // only cancels the loop and closes the transport, so the order is safe.
        defer { cleanup() }
        finishing = true // fn released — drain the trailing segment, then finalize
        if let serverError { throw EngineError.requestFailed(status: 0, message: serverError) }
        if let tail = try? encoder.flush(), !tail.isEmpty {
            try? await transport.send(RealtimeClientEvent.audioAppend(pcm16: tail).encoded())
        }
        // Commit any audio VAD hasn't auto-committed yet (the segment after the last
        // pause). Yields either a `committed`+`completed` pair or an empty-commit.
        try await transport.send(RealtimeClientEvent.audioCommit.encoded())
        let text: String = try await withCheckedThrowingContinuation { continuation in
            if let completedTranscript {
                continuation.resume(returning: completedTranscript)
            } else if let serverError {
                continuation.resume(throwing: EngineError.requestFailed(status: 0, message: serverError))
            } else {
                finishContinuation = continuation
            }
        }
        return Transcript(text: text, engineID: "realtime")
    }

    func cancel() {
        cleanup()
    }

    private func cleanup() {
        receiveLoop?.cancel()
        receiveLoop = nil
        transport.close()
    }

    private func runReceiveLoop() async {
        while !Task.isCancelled {
            guard let data = try? await transport.receive() else {
                deliver(error: serverError ?? "realtime connection lost")
                return
            }
            guard let event = try? RealtimeServerEvent.decode(data) else { continue }
            switch event {
            case .transcriptDelta(let delta):
                currentSegmentDeltas += delta
                onPartial?(liveCumulative()) // cumulative; synchronous, no MainActor hop
            case .segmentCommitted:
                openItems += 1
                if finishing { finalCommitSeen = true } // post-release commit = trailing segment
            case .transcriptCompleted(let transcript):
                let segment = transcript.isEmpty
                    ? currentSegmentDeltas.trimmingCharacters(in: .whitespaces)
                    : transcript
                if !segment.isEmpty { finalSegments.append(segment) }
                currentSegmentDeltas = ""
                openItems = max(0, openItems - 1)
                onPartial?(liveCumulative())
                if tryFinalize() { return }
            case .commitEmpty:
                // The trailing finish() commit had no new audio (VAD already drained
                // everything). Mark the boundary seen and finalize once segments settle.
                if finishing { finalCommitSeen = true; if tryFinalize() { return } }
            case .error(let message):
                deliver(error: message)
                return
            case .ignored:
                continue
            }
        }
    }

    /// Resolves finish() once fn is released, the trailing commit is acknowledged,
    /// and every committed segment has completed. Returns true when it finalized.
    private func tryFinalize() -> Bool {
        guard finishing, finalCommitSeen, openItems == 0, completedTranscript == nil else { return false }
        let result = finalSegments.isEmpty
            ? liveCumulative().trimmingCharacters(in: .whitespaces)
            : finalSegments.joined(separator: " ")
        completedTranscript = result
        finishContinuation?.resume(returning: result)
        finishContinuation = nil
        return true
    }

    private func deliver(error message: String) {
        serverError = message
        finishContinuation?.resume(throwing: EngineError.requestFailed(status: 0, message: message))
        finishContinuation = nil
    }
}

extension OpenAIRealtimeSession: LiveDictationSession {}
