import Foundation
import Observation

enum DictationState: Equatable {
    case idle
    case recording
    case transcribing
    case cleaning
    case inserting
    case error(String)
}

struct DictationResult: Equatable {
    let rawText: String
    let cleanedText: String
    let duration: TimeInterval
}

/// Orchestrates one dictation at a time: idle → recording → transcribing → cleaning → inserting → idle.
/// UI observes `state`/`lastResult`. Spec §2–§3.
@MainActor
@Observable
final class DictationCoordinator {
    private(set) var state: DictationState = .idle
    private(set) var lastResult: DictationResult?

    private let recorder: AudioRecording
    private let engine: TranscriptionEngine
    private let cleanup: CleanupServicing
    private let inserter: TextInserting
    private let minimumHold: TimeInterval
    private var recordingStartedAt: Date?
    private var processingTask: Task<Void, Never>?

    init(recorder: AudioRecording, engine: TranscriptionEngine,
         cleanup: CleanupServicing, inserter: TextInserting,
         minimumHold: TimeInterval = 0.3) {
        self.recorder = recorder
        self.engine = engine
        self.cleanup = cleanup
        self.inserter = inserter
        self.minimumHold = minimumHold
    }

    func dictationKeyPressed() async {
        guard state == .idle || isErrorState else { return } // one dictation in flight
        do {
            state = .recording
            recordingStartedAt = Date()
            try await recorder.start()
        } catch {
            fail(error)
        }
    }

    func dictationKeyReleased() async {
        guard state == .recording else { return }
        let heldFor = Date().timeIntervalSince(recordingStartedAt ?? Date())
        if heldFor < minimumHold {
            recorder.discard()
            state = .idle
            return
        }
        processingTask = Task { await process() }
    }

    /// Test helper; also used by the app on quit.
    func waitForIdle() async {
        await processingTask?.value
    }

    private func process() async {
        do {
            state = .transcribing
            let audio = try await recorder.stop()
            let transcript = try await engine.transcribe(audio, dictionaryTerms: [])
            defer { try? FileManager.default.removeItem(at: audio.fileURL) } // spec §8: discard audio

            state = .cleaning
            let cleaned: String
            do {
                cleaned = try await cleanup.clean(transcript.text, dictionaryTerms: [])
            } catch {
                cleaned = transcript.text // spec §6: raw transcript beats nothing
            }

            state = .inserting
            try await inserter.insert(cleaned)
            lastResult = DictationResult(rawText: transcript.text, cleanedText: cleaned,
                                         duration: audio.duration)
            state = .idle
        } catch {
            recorder.discard()
            fail(error)
        }
    }

    private var isErrorState: Bool {
        if case .error = state { return true }
        return false
    }

    private func fail(_ error: Error) {
        state = .error((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, self.isErrorState else { return }
            self.state = .idle
        }
    }
}
