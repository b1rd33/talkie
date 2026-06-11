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
    private let maxDuration: TimeInterval
    private let notifier: Notifying?
    private let history: HistoryStore?
    private let frontmostApp: () -> (bundleID: String?, name: String?)
    private var recordingStartedAt: Date?
    private var processingTask: Task<Void, Never>?
    private var capTask: Task<Void, Never>?
    private(set) var isHandsFree = false
    /// Briefly true after a cloud→local fallback insert — the pill flashes "offline".
    private(set) var offlineBadgeVisible = false
    private var targetApp: (bundleID: String?, name: String?) = (nil, nil)
    private let dictionaryTermsProvider: () -> [String]
    private let cleanupLevelProvider: () -> CleanupLevel
    private let stylePresetProvider: (String?) -> StylePreset
    private let pinnedLanguageProvider: () -> String?
    private var activeTerms: [String] = []
    private var activeLevel: CleanupLevel = .high
    private var activeStyle: StylePreset = .neutral
    /// Bumped after every successful insert — the pill's checkmark flash observes it.
    private(set) var lastCompletedAt: Date?
    /// Set when cleanup failed and raw ASR text was inserted (spec §6/§10) — the
    /// pill renders a subtle warning while true. Mirrors Phase 3's offlineBadgeVisible.
    private(set) var cleanupDegraded = false

    init(recorder: AudioRecording, engine: TranscriptionEngine,
         cleanup: CleanupServicing, inserter: TextInserting,
         minimumHold: TimeInterval = 0.3, maxDuration: TimeInterval = 1200,
         notifier: Notifying? = nil,
         history: HistoryStore? = nil,
         frontmostApp: @escaping () -> (bundleID: String?, name: String?) = { (nil, nil) },
         dictionaryTermsProvider: @escaping () -> [String] = { [] },
         cleanupLevelProvider: @escaping () -> CleanupLevel = { .high },
         stylePresetProvider: @escaping (String?) -> StylePreset = { _ in .neutral },
         pinnedLanguageProvider: @escaping () -> String? = { nil }) {
        self.recorder = recorder
        self.engine = engine
        self.cleanup = cleanup
        self.inserter = inserter
        self.minimumHold = minimumHold
        self.maxDuration = maxDuration
        self.notifier = notifier
        self.history = history
        self.frontmostApp = frontmostApp
        self.dictionaryTermsProvider = dictionaryTermsProvider
        self.cleanupLevelProvider = cleanupLevelProvider
        self.stylePresetProvider = stylePresetProvider
        self.pinnedLanguageProvider = pinnedLanguageProvider
    }

    func dictationKeyPressed() async {
        if isHandsFree, state == .recording {
            isHandsFree = false
            beginProcessing()
            return
        }
        guard state == .idle || isErrorState else { return } // one dictation in flight
        targetApp = frontmostApp()
        activeTerms = dictionaryTermsProvider()
        activeLevel = cleanupLevelProvider()
        activeStyle = stylePresetProvider(targetApp.bundleID)
        do {
            state = .recording
            recordingStartedAt = Date()
            try await recorder.start()
            capTask?.cancel()
            capTask = Task { [weak self, maxDuration] in
                try? await Task.sleep(for: .seconds(maxDuration))
                guard let self, !Task.isCancelled, self.state == .recording else { return }
                self.isHandsFree = false
                self.notifier?.notify(title: "Dictation auto-stopped",
                                      body: "Reached the 20-minute limit — processing what you said.")
                self.beginProcessing()
            }
        } catch {
            fail(error)
        }
    }

    func dictationKeyReleased() async {
        guard state == .recording, !isHandsFree else { return }
        let heldFor = Date().timeIntervalSince(recordingStartedAt ?? Date())
        if heldFor < minimumHold {
            capTask?.cancel()
            recorder.discard()
            state = .idle
            return
        }
        beginProcessing()
    }

    func handsFreeToggled() async {
        if state == .recording, isHandsFree {
            isHandsFree = false
            beginProcessing()
        } else if state == .idle || isErrorState {
            isHandsFree = true
            await dictationKeyPressed()
        }
    }

    private func beginProcessing() {
        capTask?.cancel()
        isHandsFree = false
        processingTask = Task { await process() }
    }

    /// Test helper; also used by the app on quit.
    func waitForIdle() async {
        await processingTask?.value
    }

    /// Cancels the in-flight dictation: recording is discarded; transcription and
    /// cleanup are interrupted cooperatively. Inserting is past the point of no return.
    func cancel() {
        switch state {
        case .recording:
            processingTask?.cancel() // a release may already have queued process() — kill it pre-start
            capTask?.cancel()
            isHandsFree = false
            recorder.discard()
            history?.save(rawText: "", cleanedText: "", appBundleID: targetApp.bundleID,
                          appName: targetApp.name, duration: 0, engine: "openai", status: .cancelled)
            state = .idle
        case .transcribing, .cleaning:
            processingTask?.cancel()
        case .idle, .inserting, .error:
            break
        }
    }

    private func process() async {
        guard state == .recording else { return } // cancelled (or superseded) before this task started
        var audioURL: URL?
        do {
            state = .transcribing
            let audio = try await recorder.stop()
            audioURL = audio.fileURL
            let transcript = try await engine.transcribe(audio, dictionaryTerms: activeTerms)
            try Task.checkCancellation()

            let cleaned: String
            if activeLevel == .none {
                cleaned = transcript.text // spec §6: None = raw ASR text, no LLM call
            } else {
                state = .cleaning
                do {
                    cleaned = try await cleanup.clean(transcript.text, dictionaryTerms: activeTerms,
                                                      level: activeLevel, style: activeStyle,
                                                      pinnedLanguage: pinnedLanguageProvider())
                } catch {
                    cleaned = transcript.text // spec §6: raw transcript beats nothing
                    cleanupDegraded = true    // spec §6/§10: badge the pill with a subtle warning
                    Task { try? await Task.sleep(for: .seconds(4)); self.cleanupDegraded = false }
                }
            }
            try Task.checkCancellation() // a cancelled cleanup must not insert raw text

            state = .inserting
            try await inserter.insert(cleaned)
            lastResult = DictationResult(rawText: transcript.text, cleanedText: cleaned,
                                         duration: audio.duration)
            lastCompletedAt = Date()
            state = .idle
            if transcript.usedFallback {
                offlineBadgeVisible = true
                Task { try? await Task.sleep(for: .seconds(4)); self.offlineBadgeVisible = false }
            }
            history?.save(rawText: transcript.text, cleanedText: cleaned,
                          appBundleID: targetApp.bundleID, appName: targetApp.name,
                          duration: audio.duration, engine: transcript.engineID, status: .completed)
            try? FileManager.default.removeItem(at: audio.fileURL) // spec §8: discard audio on success
        } catch is CancellationError {
            recorder.discard()
            state = .idle
            history?.save(rawText: "", cleanedText: "", appBundleID: targetApp.bundleID,
                          appName: targetApp.name, duration: 0, engine: "openai", status: .cancelled)
        } catch {
            recorder.discard()
            fail(error)
            // spec §10 row 1 / §8: failed dictations keep their audio for retry.
            var keptPath: String?
            if let audioURL {
                let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("Talkie/FailedAudio", isDirectory: true)
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let dest = dir.appendingPathComponent("\(UUID().uuidString).m4a")
                if (try? FileManager.default.moveItem(at: audioURL, to: dest)) != nil {
                    keptPath = dest.path
                }
            }
            history?.save(rawText: "", cleanedText: "", appBundleID: targetApp.bundleID,
                          appName: targetApp.name, duration: 0, engine: "openai", status: .failed,
                          audioPath: keptPath)
        }
    }

    private var isErrorState: Bool {
        if case .error = state { return true }
        return false
    }

    private func fail(_ error: Error) {
        if let engineError = error as? EngineError, engineError == .missingAPIKey {
            notifier?.notify(title: "API key missing",
                             body: "Add your OpenAI key in Talkie's Settings → Engines.")
        } else if let audioError = error as? AudioError, case .microphoneDenied = audioError {
            notifier?.notify(title: "Microphone unavailable",
                             body: "Check System Settings → Privacy & Security → Microphone.")
        }
        state = .error((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, self.isErrorState else { return }
            self.state = .idle
        }
    }
}
