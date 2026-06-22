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

/// A hotkey input intent. The monitor emits these; the coordinator drains them in
/// strict order so one gesture's async handling completes before the next begins.
enum HotkeyGesture {
    case press
    case release
    case toggleHandsFree
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
    private let cleanupModelProvider: () -> String?
    private let keepRecordingsProvider: () -> Bool
    private let instantSkipCleanupProvider: () -> Bool
    private let liveTypeProvider: () -> Bool
    private let liveInserter: LiveTextInserting?
    private let entitlement: (() -> EntitlementError?)?
    private let liveSessionFactory: (@MainActor (_ onPartial: @escaping PartialTranscriptSink) async throws -> LiveDictationSession)?
    private var liveSession: LiveDictationSession?
    private var liveChunkContinuation: AsyncStream<[Float]>.Continuation?
    private var liveFeedTask: Task<Void, Never>?
    /// The realtime session's `@Sendable` partial sink writes the latest cumulative
    /// string here from its actor loop; a main-actor pump (no per-delta hop) reads it.
    private let liveBox = LiveTranscriptBox()
    private var livePumpTask: Task<Void, Never>?
    /// Latest streamed text while recording in instant mode (throttled ~12.5 Hz).
    private(set) var liveTranscript: String = ""
    private var activeTerms: [String] = []
    private var activeLevel: CleanupLevel = .high
    private var activeStyle: StylePreset = .neutral
    /// Press-time snapshot of instantSkipCleanup (same contract as activeLevel).
    private var activeInstantSkipCleanup = false
    /// Press-time snapshot of instantLiveType; whether a live session was created.
    private var activeLiveType = false
    private var liveTapActive = false
    /// Bumped after every successful insert — the pill's checkmark flash observes it.
    private(set) var lastCompletedAt: Date?
    /// Set when cleanup failed and raw ASR text was inserted (spec §6/§10) — the
    /// pill renders a subtle warning while true. Mirrors Phase 3's offlineBadgeVisible.
    private(set) var cleanupDegraded = false
    /// Human-readable reason cleanup failed, shown as the degraded badge's tooltip.
    private(set) var cleanupFailureReason: String?
    /// Auto-clears the degraded badge; cancelled when a new dictation starts so a
    /// stale warning can't bleed onto the next completion.
    private var cleanupDegradeResetTask: Task<Void, Never>?

    init(recorder: AudioRecording, engine: TranscriptionEngine,
         cleanup: CleanupServicing, inserter: TextInserting,
         minimumHold: TimeInterval = 0.3, maxDuration: TimeInterval = 1200,
         notifier: Notifying? = nil,
         history: HistoryStore? = nil,
         frontmostApp: @escaping () -> (bundleID: String?, name: String?) = { (nil, nil) },
         dictionaryTermsProvider: @escaping () -> [String] = { [] },
         cleanupLevelProvider: @escaping () -> CleanupLevel = { .high },
         stylePresetProvider: @escaping (String?) -> StylePreset = { _ in .neutral },
         pinnedLanguageProvider: @escaping () -> String? = { nil },
         cleanupModelProvider: @escaping () -> String? = { nil },
         keepRecordingsProvider: @escaping () -> Bool = { false },
         instantSkipCleanupProvider: @escaping () -> Bool = { false },
         liveTypeProvider: @escaping () -> Bool = { false },
         liveInserter: LiveTextInserting? = nil,
         entitlement: (() -> EntitlementError?)? = nil,
         liveSessionFactory: (@MainActor (_ onPartial: @escaping PartialTranscriptSink) async throws -> LiveDictationSession)? = nil) {
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
        self.cleanupModelProvider = cleanupModelProvider
        self.keepRecordingsProvider = keepRecordingsProvider
        self.instantSkipCleanupProvider = instantSkipCleanupProvider
        self.liveTypeProvider = liveTypeProvider
        self.liveInserter = liveInserter
        self.entitlement = entitlement
        self.liveSessionFactory = liveSessionFactory
    }

    /// FIFO buffer of pending hotkey gestures + the single task draining them.
    /// Hotkey callbacks are sync, but their handlers suspend at `recorder.start/stop`;
    /// spawning a Task per callback let them interleave across those awaits and corrupt
    /// shared state (the hands-free double-tap race). Serializing through one drainer
    /// guarantees each gesture's handler runs to completion before the next starts.
    private var gestureQueue: [(gesture: HotkeyGesture, at: Date)] = []
    private var gestureTask: Task<Void, Never>?

    /// Enqueue a hotkey gesture for ordered handling. Safe to call from any sync
    /// hotkey callback; all mutation here is main-actor isolated. `at` captures the
    /// physical event time at enqueue so handlers measure real hold duration rather
    /// than how long the queue (incl. recorder startup) took to reach them.
    func handleGesture(_ gesture: HotkeyGesture, at: Date = Date()) {
        gestureQueue.append((gesture, at))
        guard gestureTask == nil else { return } // a drainer is already running
        gestureTask = Task { [weak self] in
            guard let self else { return }
            while !self.gestureQueue.isEmpty {
                let next = self.gestureQueue.removeFirst()
                switch next.gesture {
                case .press: await self.dictationKeyPressed(at: next.at)
                case .release: await self.dictationKeyReleased(at: next.at)
                case .toggleHandsFree: await self.handsFreeToggled(at: next.at)
                }
            }
            self.gestureTask = nil
        }
    }

    /// Test/shutdown helper: await the in-flight gesture drainer.
    func waitForGestures() async {
        await gestureTask?.value
    }

    func dictationKeyPressed(at pressedAt: Date = Date()) async {
        // Hands-free is a symmetric double-tap toggle (start AND stop via
        // handsFreeToggled). A single press must NOT stop it — otherwise the two
        // presses of a stop-double-tap bounce it off-then-on. So while hands-free
        // is recording, a stray press falls through to the guard below and no-ops.
        guard state == .idle || isErrorState else { return } // one dictation in flight
        if let entitlement, let gateError = entitlement() {
            fail(gateError) // fail() disarms hands-free
            return
        }
        clearCleanupDegraded() // a fresh dictation starts with a clean slate
        liveTranscript = ""     // clear any stale streamed preview
        liveBox.clear()
        liveInserter?.reset()
        liveTapActive = false
        targetApp = frontmostApp()
        activeTerms = dictionaryTermsProvider()
        activeLevel = cleanupLevelProvider()
        activeStyle = stylePresetProvider(targetApp.bundleID)
        activeInstantSkipCleanup = instantSkipCleanupProvider()
        activeLiveType = liveTypeProvider()
        do {
            state = .recording
            recordingStartedAt = pressedAt
            try await recorder.start()
            guard state == .recording else {
                // Released or cancelled while the engine was starting — the discard
                // that ran during the await was a no-op (isRecording was still false).
                // Without this, the engine (and macOS's orange mic indicator) stays on.
                recorder.discard()
                return
            }
            if let liveSessionFactory {
                let (stream, continuation) = AsyncStream.makeStream(of: [Float].self)
                liveChunkContinuation = continuation
                recorder.chunkConsumer = { continuation.yield($0) } // buffers while the socket connects
                do {
                    let box = liveBox
                    let session = try await liveSessionFactory { box.set($0) } // @Sendable: no actor hop
                    liveSession = session
                    liveTapActive = true
                    startLivePump() // drain the box to liveTranscript at ~12.5 Hz
                    liveFeedTask = Task { // ONE consumer — replays the backlog, preserves order
                        for await samples in stream { await session.feed(samples) }
                    }
                } catch {
                    unhookLiveTap() // batch path still works; not an error
                }
            }
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

    func dictationKeyReleased(at releasedAt: Date = Date()) async {
        guard state == .recording, !isHandsFree else { return }
        // Measure physical hold (release event time − press event time), NOT handler
        // run time — the serial queue may have delayed this handler behind a slow start.
        let heldFor = releasedAt.timeIntervalSince(recordingStartedAt ?? releasedAt)
        if heldFor < minimumHold {
            capTask?.cancel()
            recorder.discard()
            unhookLiveTap()
            liveFeedTask?.cancel()
            liveFeedTask = nil
            if let liveSession { await liveSession.cancel() }
            liveSession = nil
            state = .idle
            return
        }
        beginProcessing()
    }

    /// Detaches the chunk tap and ends the feed task's stream.
    private func unhookLiveTap() {
        recorder.chunkConsumer = nil
        liveChunkContinuation?.finish()
        liveChunkContinuation = nil
        stopLivePump()
    }

    /// Drains the lock-box into `liveTranscript` on the main actor at ~25 Hz so
    /// the socket loop never blocks on UI and the pill never re-renders per delta.
    private func startLivePump() {
        livePumpTask?.cancel()
        livePumpTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(40))
                guard let self else { return }
                let latest = self.liveBox.get()
                if latest != self.liveTranscript {
                    self.liveTranscript = latest
                    // Live typing rides the same throttle — coalesced, never per-delta
                    // keystrokes. Best-effort: a secure-field throw is ignored here and
                    // surfaces on the final flush in process().
                    //
                    // Only type while focus is still on the press-time target. If the
                    // user (or the system) moves focus mid-dictation, pause typing so
                    // keystrokes never land in the wrong app; resume when focus returns.
                    // The preview (liveTranscript) keeps updating regardless.
                    if self.activeLiveType,
                       self.frontmostApp().bundleID == self.targetApp.bundleID {
                        try? self.liveInserter?.type(upTo: latest)
                    }
                }
            }
        }
    }

    private func stopLivePump() {
        livePumpTask?.cancel()
        livePumpTask = nil
    }

    func handsFreeToggled(at: Date = Date()) async {
        if state == .recording, isHandsFree {
            isHandsFree = false
            beginProcessing()
        } else if state == .idle || isErrorState {
            isHandsFree = true
            await dictationKeyPressed(at: at)
        }
    }

    private func beginProcessing() {
        capTask?.cancel()
        isHandsFree = false
        processingTask = Task { await process() }
    }

    /// Resets the cleanup-degraded badge + reason and cancels its pending auto-clear.
    private func clearCleanupDegraded() {
        cleanupDegradeResetTask?.cancel()
        cleanupDegradeResetTask = nil
        cleanupDegraded = false
        cleanupFailureReason = nil
    }

    /// Test helper; also used by the app on quit.
    func waitForIdle() async {
        await processingTask?.value
    }

    /// Cancels the in-flight dictation: recording is discarded; transcription and
    /// cleanup are interrupted cooperatively. Inserting is past the point of no return.
    func cancel() {
        // Drop any gestures queued behind the one being cancelled, so a pending
        // toggle/press can't start a fresh dictation after the user aborted.
        gestureQueue.removeAll()
        switch state {
        case .recording:
            processingTask?.cancel() // a release may already have queued process() — kill it pre-start
            capTask?.cancel()
            isHandsFree = false
            unhookLiveTap()
            liveFeedTask?.cancel()
            liveFeedTask = nil
            if let liveSession { Task { await liveSession.cancel() } }
            liveSession = nil
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
            let transcript: Transcript
            // Set ONLY on the single success path; a batch fallback below leaves it
            // false. This is the unambiguous "instant genuinely ran" signal — never
            // infer it from engineMode (which still says "instant" after a fallback).
            var usedRealtime = false
            if let liveSession {
                self.liveSession = nil
                unhookLiveTap()
                await liveFeedTask?.value // backlog fully fed before the commit
                liveFeedTask = nil
                do {
                    transcript = try await liveSession.finish()
                    usedRealtime = true
                } catch is CancellationError {
                    throw CancellationError() // Esc mid-finish must not trigger a paid batch call
                } catch {
                    // finish() self-cleans on every exit (Task 4) — no session.cancel() needed here
                    transcript = try await engine.transcribe(audio, dictionaryTerms: activeTerms)
                }
            } else {
                transcript = try await engine.transcribe(audio, dictionaryTerms: activeTerms)
            }
            try Task.checkCancellation()

            // Skip cleanup only when the user asked (instantSkipCleanup) and instant
            // genuinely ran. Live typing alone no longer forces raw: with cleanup on,
            // the live-typed raw is erased and replaced by the cleaned text below.
            // Collapses ANY base level (incl. .custom) to .none when skipping.
            let liveTypeAttempted = activeLiveType && liveTapActive
            let effectiveLevel: CleanupLevel = (activeInstantSkipCleanup && (usedRealtime || liveTypeAttempted)) ? .none : activeLevel
            let cleaned: String
            if effectiveLevel == .none {
                cleaned = transcript.text // spec §6: None = raw ASR text, no LLM call
            } else {
                state = .cleaning
                do {
                    cleaned = try await cleanup.clean(transcript.text, dictionaryTerms: activeTerms,
                                                      level: effectiveLevel, style: activeStyle,
                                                      pinnedLanguage: pinnedLanguageProvider())
                } catch {
                    cleaned = transcript.text // spec §6: raw transcript beats nothing
                    cleanupDegraded = true    // spec §6/§10: badge the pill with a subtle warning
                    cleanupFailureReason = (error as? LocalizedError)?.errorDescription
                        ?? "Cleanup failed — inserted the raw transcript."
                    cleanupDegradeResetTask?.cancel()
                    cleanupDegradeResetTask = Task { [weak self] in
                        try? await Task.sleep(for: .seconds(4))
                        guard !Task.isCancelled else { return }
                        self?.cleanupDegraded = false
                        self?.cleanupFailureReason = nil
                    }
                }
            }
            try Task.checkCancellation() // a cancelled cleanup must not insert raw text

            state = .inserting
            // Never post a keystroke into an app other than the press-time target: if
            // focus left before release (the user switched apps), leave the text on the
            // clipboard and notify instead of pasting/typing into the wrong app.
            let onTarget = frontmostApp().bundleID == targetApp.bundleID
            let liveTypeDelivered = activeLiveType && usedRealtime
            if !onTarget {
                stopLivePump()
                inserter.copyToClipboard(cleaned)
            } else if liveTypeDelivered, let liveInserter {
                stopLivePump() // no in-flight pump append racing the final delivery
                if effectiveLevel == .none {
                    // Raw kept (skip-cleanup): cleaned == raw == what was typed. Flush
                    // the final suffix the pump may have missed; fall back to a normal
                    // insert if typing wasn't viable (AX not trusted) or realtime fell
                    // back to batch (B-7: deliver the result, not partial realtime text).
                    let viable = (try? liveInserter.type(upTo: transcript.text)) ?? false
                    if !viable { try await inserter.insert(cleaned) }
                } else {
                    // Cleanup ran: erase the live-typed raw and replace it with the cleaned
                    // text. Only insert cleaned when the erase actually succeeded — otherwise
                    // we'd leave the raw AND add cleaned (duplicate); fall back to clipboard.
                    let erased = (try? liveInserter.eraseTyped()) ?? false
                    if erased { try await inserter.insert(cleaned) }
                    else { inserter.copyToClipboard(cleaned) }
                }
            } else {
                try await inserter.insert(cleaned)
            }
            lastResult = DictationResult(rawText: transcript.text, cleanedText: cleaned,
                                         duration: audio.duration)
            lastCompletedAt = Date()
            state = .idle
            if transcript.usedFallback {
                offlineBadgeVisible = true
                Task { try? await Task.sleep(for: .seconds(4)); self.offlineBadgeVisible = false }
            }
            var keptPath: String?
            if keepRecordingsProvider() {
                keptPath = keepAudioForRetry(audio.fileURL, into: "Recordings") // spec §8: opt-in keep
            } else {
                try? FileManager.default.removeItem(at: audio.fileURL) // spec §8: discard audio on success
            }
            history?.save(rawText: transcript.text, cleanedText: cleaned,
                          appBundleID: targetApp.bundleID, appName: targetApp.name,
                          duration: audio.duration, engine: transcript.engineID, status: .completed,
                          cleanupModel: effectiveLevel == .none ? nil : cleanupModelProvider(),
                          language: pinnedLanguageProvider(), audioPath: keptPath)
        } catch is CancellationError {
            recorder.discard()
            state = .idle
            history?.save(rawText: "", cleanedText: "", appBundleID: targetApp.bundleID,
                          appName: targetApp.name, duration: 0, engine: "openai", status: .cancelled,
                          audioPath: keepAudioForRetry(audioURL))
        } catch {
            recorder.discard()
            fail(error)
            // spec §10 row 1 / §8: failed dictations keep their audio for retry.
            history?.save(rawText: "", cleanedText: "", appBundleID: targetApp.bundleID,
                          appName: targetApp.name, duration: 0, engine: "openai", status: .failed,
                          audioPath: keepAudioForRetry(audioURL))
        }
    }

    /// Moves a recorded file into Application Support for later retry (spec §8/§10).
    /// Returns the destination path, or nil if there was no file or the move failed.
    private func keepAudioForRetry(_ url: URL?, into subfolder: String = "FailedAudio") -> String? {
        guard let url else { return nil }
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Talkie/\(subfolder)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent("\(UUID().uuidString).m4a")
        guard (try? FileManager.default.moveItem(at: url, to: dest)) != nil else { return nil }
        return dest.path
    }

    /// Re-runs transcribe→clean from a failed/cancelled record's kept audio
    /// (spec §7/§10). Returns the cleaned text, or nil if the retry failed again
    /// or the kept file is gone. Delivery is the caller's job — focus is on the
    /// Hub during a retry, so paste-at-cursor would land in the wrong app
    /// (Task 7 copies the result to the clipboard).
    func retry(_ record: DictationRecord) async -> String? {
        guard state == .idle, let path = record.audioPath,
              FileManager.default.fileExists(atPath: path) else { return nil }
        let audio = RecordedAudio(fileURL: URL(fileURLWithPath: path), duration: record.durationSec)
        do {
            state = .transcribing
            let terms = dictionaryTermsProvider()
            let transcript = try await engine.transcribe(audio, dictionaryTerms: terms)
            let level = cleanupLevelProvider()
            var cleaned = transcript.text
            if level != .none {
                state = .cleaning
                cleaned = (try? await cleanup.clean(
                    transcript.text, dictionaryTerms: terms, level: level,
                    style: stylePresetProvider(record.appBundleID),
                    pinnedLanguage: pinnedLanguageProvider())) ?? transcript.text
            }
            history?.markRetried(record, rawText: transcript.text, cleanedText: cleaned)
            try? FileManager.default.removeItem(at: audio.fileURL)
            state = .idle
            return cleaned
        } catch {
            fail(error)
            return nil
        }
    }

    private var isErrorState: Bool {
        if case .error = state { return true }
        return false
    }

    private func fail(_ error: Error) {
        isHandsFree = false // any failure disarms hands-free, else the next PTT inherits it
        if let engineError = error as? EngineError, engineError == .missingAPIKey {
            if let concrete = notifier as? Notifier {
                concrete.notify(title: "API key missing",
                                body: "Add your OpenAI key in Talkie's Settings → Engines.",
                                openSettingsOnTap: true)
            } else {
                notifier?.notify(title: "API key missing",
                                 body: "Add your OpenAI key in Talkie's Settings → Engines.")
            }
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

/// Thread-safe holder for the latest cumulative partial transcript. The realtime
/// session's `@Sendable` sink writes from its actor loop; the coordinator's
/// main-actor pump reads. Monotonic cumulative strings → last-write-wins is correct.
final class LiveTranscriptBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = ""
    func set(_ s: String) { lock.lock(); value = s; lock.unlock() }
    func get() -> String { lock.lock(); defer { lock.unlock() }; return value }
    func clear() { set("") }
}
