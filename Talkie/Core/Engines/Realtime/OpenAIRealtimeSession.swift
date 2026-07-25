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
    private struct ItemState {
        var deltas = ""
        var finalTranscript: String?
        var failure: String?

        var isTerminal: Bool { finalTranscript != nil || failure != nil }
        var displayText: String { finalTranscript ?? deltas }
    }

    /// Item IDs preserve server commit order even when transcription completions
    /// arrive out of order. Duplicate commit/completion events are idempotent.
    private var committedItemIDs: [String] = []
    private var items: [String: ItemState] = [:]
    /// finish() was called — fn released; we're draining the trailing segment.
    private var finishing = false
    private enum FinalCommitOutcome { case pending, accepted, empty }
    private var finalCommitOutcome: FinalCommitOutcome = .pending
    private var finalCommitEventID: String?
    private let eventIDProvider: @Sendable () -> String
    private let settlingInterval: Duration
    private let finishTimeout: Duration
    private var activityGeneration = 0
    private var settlingTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var completedTranscript: String?
    private var serverError: String?
    private var finishContinuation: CheckedContinuation<String, Error>?

    /// Cumulative live text for the partial sink: finalized segments + the
    /// in-progress segment's deltas, spaced without doubling.
    private func liveCumulative() -> String {
        committedItemIDs.reduce(into: "") { result, id in
            let text = items[id]?.displayText ?? ""
            guard !text.isEmpty else { return }
            if result.isEmpty || result.hasSuffix(" ") || text.hasPrefix(" ") {
                result += text
            } else {
                result += " " + text
            }
        }
    }

    init(transport: RealtimeTransport, model: String, vocabulary: String?, language: String?,
         encoder: RealtimePCMEncoder, onPartial: PartialTranscriptSink? = nil,
         eventIDProvider: @escaping @Sendable () -> String = { "finish-\(UUID().uuidString)" },
         settlingInterval: Duration = .milliseconds(200),
         finishTimeout: Duration = .seconds(8)) {
        self.transport = transport
        self.model = model
        self.vocabulary = vocabulary
        self.language = language
        self.encoder = encoder
        self.onPartial = onPartial
        self.eventIDProvider = eventIDProvider
        self.settlingInterval = settlingInterval
        self.finishTimeout = finishTimeout
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
        let eventID = eventIDProvider()
        finalCommitEventID = eventID
        finalCommitOutcome = .pending
        try await transport.send(RealtimeClientEvent.audioCommit(eventID: eventID).encoded())
        startFinishTimeout()
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
        settlingTask?.cancel()
        settlingTask = nil
        timeoutTask?.cancel()
        timeoutTask = nil
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
            case .transcriptDelta(let itemID, let delta):
                guard items[itemID]?.isTerminal != true else { continue }
                items[itemID, default: ItemState()].deltas += delta
                noteActivity()
                onPartial?(liveCumulative()) // cumulative; synchronous, no MainActor hop
                scheduleSettlingIfEligible()
            case .segmentCommitted(let itemID):
                noteActivity()
                if !committedItemIDs.contains(itemID) { committedItemIDs.append(itemID) }
                if items[itemID] == nil { items[itemID] = ItemState() }
                if finishing { finalCommitOutcome = .accepted }
                scheduleSettlingIfEligible()
            case .transcriptCompleted(let itemID, let transcript):
                guard items[itemID]?.isTerminal != true else { continue }
                var item = items[itemID, default: ItemState()]
                let completed = transcript.isEmpty
                    ? item.deltas.trimmingCharacters(in: .whitespacesAndNewlines)
                    : transcript
                item.finalTranscript = completed
                items[itemID] = item
                noteActivity()
                onPartial?(liveCumulative())
                scheduleSettlingIfEligible()
            case .transcriptionFailed(let itemID, let message):
                items[itemID, default: ItemState()].failure = message
                deliver(error: "transcription failed for \(itemID): \(message)")
                return
            case .commitEmpty(let clientEventID):
                guard finishing, clientEventID == finalCommitEventID else { continue }
                noteActivity()
                finalCommitOutcome = .empty
                scheduleSettlingIfEligible()
            case .error(let message, _):
                deliver(error: message)
                return
            case .ignored:
                continue
            }
        }
    }

    private func noteActivity() {
        activityGeneration += 1
        settlingTask?.cancel()
        settlingTask = nil
    }

    private var isReadyToSettle: Bool {
        guard finishing, completedTranscript == nil else { return false }
        guard finalCommitOutcome != .pending else { return false }
        return committedItemIDs.allSatisfy { items[$0]?.isTerminal == true }
    }

    /// The server does not echo a successful commit's client event ID. A short
    /// quiet window therefore closes the race where a delayed VAD commit is
    /// observed before the manual finish commit's committed item.
    private func scheduleSettlingIfEligible() {
        guard isReadyToSettle else { return }
        let generation = activityGeneration
        settlingTask = Task { [weak self, settlingInterval] in
            try? await Task.sleep(for: settlingInterval)
            guard !Task.isCancelled else { return }
            await self?.finalizeIfStable(generation: generation)
        }
    }

    private func finalizeIfStable(generation: Int) {
        guard generation == activityGeneration, isReadyToSettle else { return }
        let result = liveCumulative().trimmingCharacters(in: .whitespacesAndNewlines)
        completedTranscript = result
        finishContinuation?.resume(returning: result)
        finishContinuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
    }

    private func startFinishTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self, finishTimeout] in
            try? await Task.sleep(for: finishTimeout)
            guard !Task.isCancelled else { return }
            await self?.deliver(error: "realtime finalization timed out")
        }
    }

    private func deliver(error message: String) {
        guard completedTranscript == nil, serverError == nil else { return }
        serverError = message
        settlingTask?.cancel()
        settlingTask = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        finishContinuation?.resume(throwing: EngineError.requestFailed(status: 0, message: message))
        finishContinuation = nil
    }
}

extension OpenAIRealtimeSession: LiveDictationSession {}
