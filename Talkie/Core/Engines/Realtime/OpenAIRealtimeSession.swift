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
    private var accumulated = ""
    private var completedTranscript: String?
    private var serverError: String?
    private var finishContinuation: CheckedContinuation<String, Error>?

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
        if let serverError { throw EngineError.requestFailed(status: 0, message: serverError) }
        if let tail = try? encoder.flush(), !tail.isEmpty {
            try? await transport.send(RealtimeClientEvent.audioAppend(pcm16: tail).encoded())
        }
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
                accumulated += delta
                onPartial?(accumulated) // cumulative; synchronous, no MainActor hop
            case .transcriptCompleted(let transcript):
                let final = transcript.isEmpty ? accumulated : transcript
                completedTranscript = final
                onPartial?(final)
                finishContinuation?.resume(returning: final)
                finishContinuation = nil
                return
            case .error(let message):
                deliver(error: message)
                return
            case .ignored:
                continue
            }
        }
    }

    private func deliver(error message: String) {
        serverError = message
        finishContinuation?.resume(throwing: EngineError.requestFailed(status: 0, message: message))
        finishContinuation = nil
    }
}

extension OpenAIRealtimeSession: LiveDictationSession {}
