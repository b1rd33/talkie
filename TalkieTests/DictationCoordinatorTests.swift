import XCTest
@testable import Talkie

@MainActor
final class DictationCoordinatorTests: XCTestCase {
    // MARK: mocks

    final class MockRecorder: AudioRecording {
        var latestLevel: Float = 0
        var chunkConsumer: (([Float]) -> Void)?
        var started = 0
        var stopped = 0
        var discarded = 0
        var startError: Error?
        var startDelay: Duration?
        /// Mirrors the real engine: true once start() completes, false on stop/discard.
        var isRunning = false
        var stopURL = URL(fileURLWithPath: "/tmp/fake.m4a")
        func start() async throws {
            if let startDelay { try? await Task.sleep(for: startDelay) }
            started += 1
            if let startError { throw startError }
            isRunning = true
        }
        func stop() async throws -> RecordedAudio {
            stopped += 1
            isRunning = false
            return RecordedAudio(fileURL: stopURL, duration: 2.0)
        }
        func discard() {
            discarded += 1
            isRunning = false
        }
    }

    final class MockEngine: TranscriptionEngine, @unchecked Sendable {
        var result: Result<Transcript, Error>
        private(set) var receivedTerms: [[String]] = []
        init(result: Result<Transcript, Error> = .success(Transcript(text: "raw text"))) {
            self.result = result
        }
        func transcribe(_ audio: RecordedAudio, dictionaryTerms: [String]) async throws -> Transcript {
            receivedTerms.append(dictionaryTerms)
            return try result.get()
        }
    }

    final class MockCleanup: CleanupServicing, @unchecked Sendable {
        var result: Result<String, Error>
        private(set) var calls: [(terms: [String], level: CleanupLevel, style: StylePreset, language: String?)] = []
        init(result: Result<String, Error> = .success("Clean text.")) {
            self.result = result
        }
        func clean(_ transcript: String, dictionaryTerms: [String], level: CleanupLevel,
                   style: StylePreset, pinnedLanguage: String?) async throws -> String {
            calls.append((dictionaryTerms, level, style, pinnedLanguage))
            return try result.get()
        }
    }

    final class MockInserter: TextInserting {
        var inserted: [String] = []
        func insert(_ text: String) async throws { inserted.append(text) }
    }

    private func makeCoordinator(
        recorder: MockRecorder? = nil,
        engine: MockEngine = MockEngine(),
        cleanup: MockCleanup = MockCleanup(),
        inserter: MockInserter? = nil,
        history: HistoryStore? = nil,
        keepRecordings: @escaping () -> Bool = { false }
    ) -> (DictationCoordinator, MockRecorder, MockInserter) {
        // Mocks conform to @MainActor protocols, so their inits can't run in
        // nonisolated default-argument position — construct them here instead.
        let recorder = recorder ?? MockRecorder()
        let inserter = inserter ?? MockInserter()
        let c = DictationCoordinator(recorder: recorder, engine: engine,
                                     cleanup: cleanup, inserter: inserter,
                                     minimumHold: 0, // disable debounce in most tests
                                     history: history,
                                     keepRecordingsProvider: keepRecordings)
        return (c, recorder, inserter)
    }

    func testKeepRecordingsStampsAudioPathOnSuccess() async throws {
        let history = try HistoryStore(inMemory: true)
        let recorder = MockRecorder()
        recorder.stopURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("talkie-keep-test-\(UUID().uuidString).m4a")
        try Data("x".utf8).write(to: recorder.stopURL)
        defer { try? FileManager.default.removeItem(at: recorder.stopURL) }
        let (coordinator, _, _) = makeCoordinator(recorder: recorder, history: history,
                                                  keepRecordings: { true })
        await coordinator.dictationKeyPressed()
        await coordinator.dictationKeyReleased()
        await coordinator.waitForIdle()
        let record = history.recent(limit: 1)[0]
        XCTAssertEqual(record.status, .completed)
        XCTAssertNotNil(record.audioPath) // moved to Recordings/, not deleted
    }

    // MARK: tests

    func testHappyPathInsertsCleanedText() async {
        let (coordinator, recorder, inserter) = makeCoordinator()
        await coordinator.dictationKeyPressed()
        XCTAssertEqual(coordinator.state, .recording)
        XCTAssertEqual(recorder.started, 1)
        await coordinator.dictationKeyReleased()
        await coordinator.waitForIdle()
        XCTAssertEqual(inserter.inserted, ["Clean text."])
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertEqual(coordinator.lastResult?.cleanedText, "Clean text.")
        XCTAssertEqual(coordinator.lastResult?.rawText, "raw text")
    }

    func testReleaseDuringEngineStartupStopsTheEngine() async throws {
        // Mic-pinned-on race (live bug 2026-06-11): release lands while
        // recorder.start() is still awaiting — its discard() no-ops because the
        // engine isn't running yet. The coordinator must re-check after the await
        // and discard, or the engine (and macOS's orange mic indicator) stays on.
        let recorder = MockRecorder()
        recorder.startDelay = .milliseconds(80)
        let coordinator = DictationCoordinator(recorder: recorder, engine: MockEngine(),
                                               cleanup: MockCleanup(), inserter: MockInserter(),
                                               minimumHold: 10) // any release is "too soon"
        let press = Task { await coordinator.dictationKeyPressed() }
        try await Task.sleep(for: .milliseconds(20)) // press in flight, engine still starting
        await coordinator.dictationKeyReleased()     // short tap → discard (no-op pre-fix)
        await press.value                            // start() completes after the release
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertFalse(recorder.isRunning, "engine left running after a tap during startup")
    }

    func testShortHoldDiscards() async {
        let recorder = MockRecorder()
        let coordinator = DictationCoordinator(recorder: recorder, engine: MockEngine(),
                                               cleanup: MockCleanup(), inserter: MockInserter(),
                                               minimumHold: 10) // 10s — release is always "too soon"
        await coordinator.dictationKeyPressed()
        await coordinator.dictationKeyReleased()
        await coordinator.waitForIdle()
        XCTAssertEqual(recorder.discarded, 1)
        XCTAssertEqual(recorder.stopped, 0)
        XCTAssertEqual(coordinator.state, .idle)
    }

    func testEngineFailureSetsErrorAndInsertsNothing() async {
        let engine = MockEngine(result: .failure(EngineError.requestFailed(status: 500, message: "boom")))
        let (coordinator, _, inserter) = makeCoordinator(engine: engine)
        await coordinator.dictationKeyPressed()
        await coordinator.dictationKeyReleased()
        await coordinator.waitForIdle()
        XCTAssertTrue(inserter.inserted.isEmpty)
        guard case .error = coordinator.state else { return XCTFail("expected error state, got \(coordinator.state)") }
    }

    func testCleanupFailureFallsBackToRawTranscript() async {
        let cleanup = MockCleanup(result: .failure(EngineError.requestFailed(status: 503, message: "down")))
        let (coordinator, _, inserter) = makeCoordinator(cleanup: cleanup)
        await coordinator.dictationKeyPressed()
        await coordinator.dictationKeyReleased()
        await coordinator.waitForIdle()
        XCTAssertEqual(inserter.inserted, ["raw text"]) // spec §6: raw beats nothing
        XCTAssertEqual(coordinator.state, .idle)
    }

    final class MockLiveSession: LiveDictationSession {
        var fed = 0
        var finishResult: Result<Transcript, Error> = .success(Transcript(text: "live text", engineID: "realtime"))
        var cancelled = false
        func feed(_ samples: [Float]) async { fed += 1 }
        func finish() async throws -> Transcript { try finishResult.get() }
        func cancel() async { cancelled = true }
    }

    func testInstantModeUsesLiveTranscript() async {
        let live = MockLiveSession()
        let recorder = MockRecorder()
        let inserter = MockInserter()
        let coordinator = DictationCoordinator(recorder: recorder, engine: MockEngine(),
                                               cleanup: MockCleanup(), inserter: inserter,
                                               minimumHold: 0,
                                               liveSessionFactory: { live })
        await coordinator.dictationKeyPressed()
        XCTAssertNotNil(recorder.chunkConsumer) // chunks are being forwarded
        await coordinator.dictationKeyReleased()
        await coordinator.waitForIdle()
        XCTAssertEqual(inserter.inserted, ["Clean text."]) // cleanup ran on the LIVE transcript
        XCTAssertEqual(coordinator.lastResult?.rawText, "live text")
    }

    func testLiveFailureFallsBackToBatchEngine() async {
        let live = MockLiveSession()
        live.finishResult = .failure(EngineError.requestFailed(status: 0, message: "socket died"))
        let recorder = MockRecorder()
        let inserter = MockInserter()
        let coordinator = DictationCoordinator(recorder: recorder, engine: MockEngine(), // returns "raw text"
                                               cleanup: MockCleanup(), inserter: inserter,
                                               minimumHold: 0,
                                               liveSessionFactory: { live })
        await coordinator.dictationKeyPressed()
        await coordinator.dictationKeyReleased()
        await coordinator.waitForIdle()
        XCTAssertEqual(coordinator.lastResult?.rawText, "raw text") // batch fallback won
        XCTAssertEqual(coordinator.state, .idle)
    }

    func testShortHoldCancelsLiveSession() async {
        let live = MockLiveSession()
        let recorder = MockRecorder()
        let coordinator = DictationCoordinator(recorder: recorder, engine: MockEngine(),
                                               cleanup: MockCleanup(), inserter: MockInserter(),
                                               minimumHold: 10,
                                               liveSessionFactory: { live })
        await coordinator.dictationKeyPressed()
        await coordinator.dictationKeyReleased()
        await coordinator.waitForIdle()
        XCTAssertTrue(live.cancelled)
        XCTAssertNil(recorder.chunkConsumer) // unhooked
    }

    func testChunksBufferedWhileSessionConnectsAreDelivered() async {
        let live = MockLiveSession()
        let recorder = MockRecorder()
        let coordinator = DictationCoordinator(recorder: recorder, engine: MockEngine(),
                                               cleanup: MockCleanup(), inserter: MockInserter(),
                                               minimumHold: 0,
                                               liveSessionFactory: {
                                                   // simulates speech landing while the socket is still
                                                   // connecting: the tap must already be wired when the
                                                   // factory runs, and the chunk must reach the session
                                                   recorder.chunkConsumer?([0.1, 0.2])
                                                   return live
                                               })
        await coordinator.dictationKeyPressed()
        await coordinator.dictationKeyReleased()
        await coordinator.waitForIdle()
        XCTAssertEqual(live.fed, 1) // the pre-connect chunk was buffered and replayed, not dropped
    }

    func testExpiredEntitlementBlocksDictationWithErrorPill() async {
        let recorder = MockRecorder()
        let coordinator = DictationCoordinator(recorder: recorder, engine: MockEngine(),
                                               cleanup: MockCleanup(), inserter: MockInserter(),
                                               minimumHold: 0, entitlement: { .expired })
        await coordinator.dictationKeyPressed()
        XCTAssertEqual(recorder.started, 0)
        guard case .error(let message) = coordinator.state else {
            return XCTFail("expected error state, got \(coordinator.state)")
        }
        XCTAssertTrue(message.contains("Trial expired"))
    }

    func testEntitledDictationProceeds() async {
        let recorder = MockRecorder()
        let coordinator = DictationCoordinator(recorder: recorder, engine: MockEngine(),
                                               cleanup: MockCleanup(), inserter: MockInserter(),
                                               minimumHold: 0, entitlement: { nil })
        await coordinator.dictationKeyPressed()
        XCTAssertEqual(coordinator.state, .recording)
        XCTAssertEqual(recorder.started, 1)
    }

    func testRetryTranscribesKeptAudioAndCompletesRecord() async throws {
        let history = try HistoryStore(inMemory: true)
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("talkie-retry-test-\(UUID().uuidString).m4a")
        try Data("fake audio".utf8).write(to: audioURL)
        history.save(rawText: "", cleanedText: "", appBundleID: nil, appName: nil,
                     duration: 2, engine: "openai", status: .failed, audioPath: audioURL.path)
        let record = history.recent(limit: 1)[0]
        let inserter = MockInserter()
        let coordinator = DictationCoordinator(
            recorder: MockRecorder(), engine: MockEngine(), cleanup: MockCleanup(),
            inserter: inserter, minimumHold: 0, history: history)
        let text = await coordinator.retry(record)
        XCTAssertEqual(text, "Clean text.")
        XCTAssertEqual(record.status, .completed)
        XCTAssertNil(record.audioPath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: audioURL.path)) // consumed on success
        XCTAssertTrue(inserter.inserted.isEmpty) // delivery is the caller's job (clipboard, Task 7)
        XCTAssertEqual(coordinator.state, .idle)
    }

    func testProvidersFeedEngineAndCleanupResolvedAtPressTime() async {
        let engine = MockEngine()
        let cleanup = MockCleanup()
        let coordinator = DictationCoordinator(
            recorder: MockRecorder(), engine: engine, cleanup: cleanup, inserter: MockInserter(),
            minimumHold: 0,
            frontmostApp: { ("com.apple.dt.Xcode", "Xcode") },
            dictionaryTermsProvider: { ["Archiev", "Talkie"] },
            cleanupLevelProvider: { .medium },
            stylePresetProvider: { bundleID in bundleID == "com.apple.dt.Xcode" ? .technical : .neutral },
            pinnedLanguageProvider: { "German" })
        await coordinator.dictationKeyPressed()
        await coordinator.dictationKeyReleased()
        await coordinator.waitForIdle()
        XCTAssertEqual(engine.receivedTerms, [["Archiev", "Talkie"]])
        XCTAssertEqual(cleanup.calls.count, 1)
        XCTAssertEqual(cleanup.calls[0].terms, ["Archiev", "Talkie"])
        XCTAssertEqual(cleanup.calls[0].level, .medium)
        XCTAssertEqual(cleanup.calls[0].style, .technical)
        XCTAssertEqual(cleanup.calls[0].language, "German")
    }

    func testLevelNoneSkipsCleanupAndInsertsRaw() async {
        let cleanup = MockCleanup()
        let inserter = MockInserter()
        let coordinator = DictationCoordinator(
            recorder: MockRecorder(), engine: MockEngine(), cleanup: cleanup, inserter: inserter,
            minimumHold: 0,
            cleanupLevelProvider: { .none })
        await coordinator.dictationKeyPressed()
        await coordinator.dictationKeyReleased()
        await coordinator.waitForIdle()
        XCTAssertTrue(cleanup.calls.isEmpty)            // spec §6: None = no LLM call
        XCTAssertEqual(inserter.inserted, ["raw text"]) // raw ASR text inserted
        XCTAssertEqual(coordinator.state, .idle)
    }

    func testSuccessfulDictationPublishesLastCompletedAt() async {
        let (coordinator, _, _) = makeCoordinator()
        XCTAssertNil(coordinator.lastCompletedAt)
        await coordinator.dictationKeyPressed()
        await coordinator.dictationKeyReleased()
        await coordinator.waitForIdle()
        XCTAssertNotNil(coordinator.lastCompletedAt)
    }

    func testFailedDictationDoesNotPublishLastCompletedAt() async {
        let engine = MockEngine(result: .failure(EngineError.requestFailed(status: 500, message: "boom")))
        let (coordinator, _, _) = makeCoordinator(engine: engine)
        await coordinator.dictationKeyPressed()
        await coordinator.dictationKeyReleased()
        await coordinator.waitForIdle()
        XCTAssertNil(coordinator.lastCompletedAt)
    }

    func testCleanupFailureInsertsRawAndFlagsDegraded() async {
        let cleanup = MockCleanup(result: .failure(EngineError.invalidResponse))
        let (coordinator, _, inserter) = makeCoordinator(cleanup: cleanup)
        XCTAssertFalse(coordinator.cleanupDegraded)
        await coordinator.dictationKeyPressed()
        await coordinator.dictationKeyReleased()
        await coordinator.waitForIdle()
        XCTAssertEqual(inserter.inserted, ["raw text"]) // spec §6: raw transcript beats nothing
        XCTAssertTrue(coordinator.cleanupDegraded)      // spec §6/§10: subtle pill warning
    }

    func testCleanupFailureStoresReason() async {
        let cleanup = MockCleanup(result: .failure(EngineError.missingAPIKey))
        let (coordinator, _, _) = makeCoordinator(cleanup: cleanup)
        await coordinator.dictationKeyPressed()
        await coordinator.dictationKeyReleased()
        await coordinator.waitForIdle()
        XCTAssertNotNil(coordinator.cleanupFailureReason)
        XCTAssertEqual(coordinator.cleanupFailureReason, EngineError.missingAPIKey.errorDescription)
    }

    func testNextDictationClearsStaleDegradedState() async {
        let cleanup = MockCleanup(result: .failure(EngineError.invalidResponse))
        let (coordinator, _, _) = makeCoordinator(cleanup: cleanup)
        await coordinator.dictationKeyPressed()
        await coordinator.dictationKeyReleased()
        await coordinator.waitForIdle()
        XCTAssertTrue(coordinator.cleanupDegraded)

        // Starting a fresh dictation must clear the stale badge immediately, so it
        // can't bleed onto the next completion's checkmark.
        await coordinator.dictationKeyPressed()
        XCTAssertEqual(coordinator.state, .recording)
        XCTAssertFalse(coordinator.cleanupDegraded)
        XCTAssertNil(coordinator.cleanupFailureReason)
        await coordinator.dictationKeyReleased()
        await coordinator.waitForIdle()
    }

    final class MockNotifier: Notifying {
        var titles: [String] = []
        func notify(title: String, body: String) { titles.append(title) }
    }

    func testSessionCapAutoStopsAndProcesses() async throws {
        let recorder = MockRecorder()
        let inserter = MockInserter()
        let notifier = MockNotifier()
        let coordinator = DictationCoordinator(recorder: recorder, engine: MockEngine(),
                                               cleanup: MockCleanup(), inserter: inserter,
                                               minimumHold: 0, maxDuration: 0.05, notifier: notifier)
        await coordinator.dictationKeyPressed()
        try await Task.sleep(for: .milliseconds(250)) // cap (50ms) fires
        await coordinator.waitForIdle()
        XCTAssertEqual(recorder.stopped, 1)
        XCTAssertEqual(inserter.inserted, ["Clean text."])
        XCTAssertEqual(notifier.titles, ["Dictation auto-stopped"]) // spec §10: cap notifies
    }

    func testHandsFreeToggleRecordsAcrossRelease() async {
        let (coordinator, recorder, inserter) = makeCoordinator()
        await coordinator.handsFreeToggled()           // starts hands-free recording
        XCTAssertEqual(coordinator.state, .recording)
        await coordinator.dictationKeyReleased()       // fn release must NOT stop it
        XCTAssertEqual(coordinator.state, .recording)
        await coordinator.handsFreeToggled()           // second toggle stops + processes
        await coordinator.waitForIdle()
        XCTAssertEqual(recorder.stopped, 1)
        XCTAssertEqual(inserter.inserted, ["Clean text."])
    }

    func testHandsFreeStopsOnSingleTapPress() async {
        let (coordinator, recorder, inserter) = makeCoordinator()
        await coordinator.handsFreeToggled()           // hands-free recording on
        await coordinator.dictationKeyPressed()        // single fn tap stops it (spec §4)
        await coordinator.waitForIdle()
        XCTAssertEqual(recorder.stopped, 1)
        XCTAssertEqual(inserter.inserted, ["Clean text."])
    }

    func testCancelDuringRecordingDiscardsAndGoesIdle() async {
        let (coordinator, recorder, inserter) = makeCoordinator()
        await coordinator.dictationKeyPressed()
        coordinator.cancel()
        XCTAssertEqual(recorder.discarded, 1)
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertTrue(inserter.inserted.isEmpty)
    }

    func testCancelDuringTranscriptionInsertsNothing() async {
        struct SlowEngine: TranscriptionEngine {
            func transcribe(_ audio: RecordedAudio, dictionaryTerms: [String]) async throws -> Transcript {
                try await Task.sleep(for: .seconds(5)) // cancellation interrupts this sleep
                return Transcript(text: "too late")
            }
        }
        let recorder = MockRecorder()
        let inserter = MockInserter()
        let coordinator = DictationCoordinator(recorder: recorder, engine: SlowEngine(),
                                               cleanup: MockCleanup(), inserter: inserter,
                                               minimumHold: 0)
        await coordinator.dictationKeyPressed()
        await coordinator.dictationKeyReleased()
        coordinator.cancel()
        await coordinator.waitForIdle()
        XCTAssertTrue(inserter.inserted.isEmpty)
        XCTAssertEqual(coordinator.state, .idle)
    }

    func testPressWhileProcessingIgnored() async {
        let (coordinator, recorder, _) = makeCoordinator()
        await coordinator.dictationKeyPressed()
        await coordinator.dictationKeyReleased() // processing starts
        await coordinator.dictationKeyPressed()  // spec §3: one dictation in flight
        await coordinator.waitForIdle()
        XCTAssertEqual(recorder.started, 1)
    }
}
