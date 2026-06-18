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
        var copied: [String] = []
        func insert(_ text: String) async throws { inserted.append(text) }
        func copyToClipboard(_ text: String) { copied.append(text) }
    }

    @MainActor
    final class MockLiveInserter: LiveTextInserting {
        var typedUpTo: [String] = []
        var resetCount = 0
        var viable = true
        func reset() { resetCount += 1 }
        @discardableResult
        func type(upTo accumulated: String) throws -> Bool { typedUpTo.append(accumulated); return viable }
        var eraseCount = 0
        @discardableResult
        func eraseTyped() throws -> Bool { eraseCount += 1; return viable }
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
        var onPartial: PartialTranscriptSink?
        func feed(_ samples: [Float]) async { fed += 1 }
        func finish() async throws -> Transcript { try finishResult.get() }
        func cancel() async { cancelled = true }
        /// Simulate a streamed partial reaching the coordinator's sink.
        func emit(_ s: String) { onPartial?(s) }
    }

    func testInstantModeUsesLiveTranscript() async {
        let live = MockLiveSession()
        let recorder = MockRecorder()
        let inserter = MockInserter()
        let coordinator = DictationCoordinator(recorder: recorder, engine: MockEngine(),
                                               cleanup: MockCleanup(), inserter: inserter,
                                               minimumHold: 0,
                                               liveSessionFactory: { _ in live })
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
                                               liveSessionFactory: { _ in live })
        await coordinator.dictationKeyPressed()
        await coordinator.dictationKeyReleased()
        await coordinator.waitForIdle()
        XCTAssertEqual(coordinator.lastResult?.rawText, "raw text") // batch fallback won
        XCTAssertEqual(coordinator.state, .idle)
    }

    // MARK: instant skip-cleanup (Part A)

    func testInstantSkipBypassesCleanupWhenRealtimeUsed() async {
        let live = MockLiveSession() // finishes "live text", engineID "realtime"
        let cleanup = MockCleanup()
        let inserter = MockInserter()
        let coordinator = DictationCoordinator(recorder: MockRecorder(), engine: MockEngine(),
                                               cleanup: cleanup, inserter: inserter, minimumHold: 0,
                                               instantSkipCleanupProvider: { true },
                                               liveSessionFactory: { _ in live })
        await coordinator.dictationKeyPressed()
        await coordinator.dictationKeyReleased()
        await coordinator.waitForIdle()
        XCTAssertTrue(cleanup.calls.isEmpty)              // no LLM polish
        XCTAssertEqual(inserter.inserted, ["live text"])  // raw streamed text
        XCTAssertEqual(coordinator.lastResult?.rawText, "live text")
        XCTAssertEqual(coordinator.state, .idle)
    }

    func testInstantSkipStillCleansWhenLiveFinishFails() async {
        let live = MockLiveSession()
        live.finishResult = .failure(EngineError.requestFailed(status: 0, message: "socket died"))
        let cleanup = MockCleanup()
        let inserter = MockInserter()
        // Falls back to MockEngine ("raw text", engineID "openai" — not realtime),
        // so skip must NOT apply: cleanup still runs.
        let coordinator = DictationCoordinator(recorder: MockRecorder(), engine: MockEngine(),
                                               cleanup: cleanup, inserter: inserter, minimumHold: 0,
                                               cleanupLevelProvider: { .high },
                                               instantSkipCleanupProvider: { true },
                                               liveSessionFactory: { _ in live })
        await coordinator.dictationKeyPressed()
        await coordinator.dictationKeyReleased()
        await coordinator.waitForIdle()
        XCTAssertEqual(cleanup.calls.count, 1)
        XCTAssertEqual(inserter.inserted, ["Clean text."])
    }

    func testInstantSkipOffRunsCleanup() async {
        let live = MockLiveSession()
        let cleanup = MockCleanup()
        let coordinator = DictationCoordinator(recorder: MockRecorder(), engine: MockEngine(),
                                               cleanup: cleanup, inserter: MockInserter(), minimumHold: 0,
                                               instantSkipCleanupProvider: { false },
                                               liveSessionFactory: { _ in live })
        await coordinator.dictationKeyPressed()
        await coordinator.dictationKeyReleased()
        await coordinator.waitForIdle()
        XCTAssertEqual(cleanup.calls.count, 1)
    }

    func testBatchModeUnaffectedByInstantSkipFlag() async {
        let cleanup = MockCleanup()
        let coordinator = DictationCoordinator(recorder: MockRecorder(), engine: MockEngine(),
                                               cleanup: cleanup, inserter: MockInserter(), minimumHold: 0,
                                               cleanupLevelProvider: { .high },
                                               instantSkipCleanupProvider: { true }) // no liveSessionFactory
        await coordinator.dictationKeyPressed()
        await coordinator.dictationKeyReleased()
        await coordinator.waitForIdle()
        XCTAssertEqual(cleanup.calls.count, 1) // batch dictation ignores the instant flag
    }

    func testInstantSkipCollapsesCustomLevel() async {
        let live = MockLiveSession()
        let cleanup = MockCleanup()
        let inserter = MockInserter()
        let coordinator = DictationCoordinator(recorder: MockRecorder(), engine: MockEngine(),
                                               cleanup: cleanup, inserter: inserter, minimumHold: 0,
                                               cleanupLevelProvider: { .custom },
                                               instantSkipCleanupProvider: { true },
                                               liveSessionFactory: { _ in live })
        await coordinator.dictationKeyPressed()
        await coordinator.dictationKeyReleased()
        await coordinator.waitForIdle()
        XCTAssertTrue(cleanup.calls.isEmpty) // .custom deliberately collapses to raw
        XCTAssertEqual(inserter.inserted, ["live text"])
    }

    func testInstantSkipWithLevelAlreadyNone() async {
        let live = MockLiveSession()
        let cleanup = MockCleanup()
        let inserter = MockInserter()
        let coordinator = DictationCoordinator(recorder: MockRecorder(), engine: MockEngine(),
                                               cleanup: cleanup, inserter: inserter, minimumHold: 0,
                                               cleanupLevelProvider: { .none },
                                               instantSkipCleanupProvider: { true },
                                               liveSessionFactory: { _ in live })
        await coordinator.dictationKeyPressed()
        await coordinator.dictationKeyReleased()
        await coordinator.waitForIdle()
        XCTAssertTrue(cleanup.calls.isEmpty)
        XCTAssertEqual(inserter.inserted, ["live text"])
    }

    func testInstantSkipRecordsNoCleanupModelInHistory() async throws {
        let history = try HistoryStore(inMemory: true)
        let live = MockLiveSession()
        let coordinator = DictationCoordinator(recorder: MockRecorder(), engine: MockEngine(),
                                               cleanup: MockCleanup(), inserter: MockInserter(),
                                               minimumHold: 0, history: history,
                                               cleanupModelProvider: { "google/gemini-2.5-flash-lite" },
                                               instantSkipCleanupProvider: { true },
                                               liveSessionFactory: { _ in live })
        await coordinator.dictationKeyPressed()
        await coordinator.dictationKeyReleased()
        await coordinator.waitForIdle()
        XCTAssertNil(history.recent(limit: 1)[0].cleanupModel)
    }

    func testInstantCleanedDictationRecordsCleanupModel() async throws {
        let history = try HistoryStore(inMemory: true)
        let live = MockLiveSession()
        let coordinator = DictationCoordinator(recorder: MockRecorder(), engine: MockEngine(),
                                               cleanup: MockCleanup(), inserter: MockInserter(),
                                               minimumHold: 0, history: history,
                                               cleanupModelProvider: { "google/gemini-2.5-flash-lite" },
                                               instantSkipCleanupProvider: { false },
                                               liveSessionFactory: { _ in live })
        await coordinator.dictationKeyPressed()
        await coordinator.dictationKeyReleased()
        await coordinator.waitForIdle()
        XCTAssertEqual(history.recent(limit: 1)[0].cleanupModel, "google/gemini-2.5-flash-lite")
    }

    func testShortHoldCancelsLiveSession() async {
        let live = MockLiveSession()
        let recorder = MockRecorder()
        let coordinator = DictationCoordinator(recorder: recorder, engine: MockEngine(),
                                               cleanup: MockCleanup(), inserter: MockInserter(),
                                               minimumHold: 10,
                                               liveSessionFactory: { _ in live })
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
                                               liveSessionFactory: { _ in
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

    // MARK: live typing (Part B4)

    func testLiveTypeSkipsFinalInsert() async {
        let live = MockLiveSession() // finishes "live text"
        let liveInserter = MockLiveInserter()
        let inserter = MockInserter()
        let cleanup = MockCleanup()
        let coordinator = DictationCoordinator(recorder: MockRecorder(), engine: MockEngine(),
                                               cleanup: cleanup, inserter: inserter, minimumHold: 0,
                                               cleanupLevelProvider: { .high },
                                               instantSkipCleanupProvider: { true }, // skip-cleanup → keep raw live text
                                               liveTypeProvider: { true },
                                               liveInserter: liveInserter,
                                               liveSessionFactory: { sink in live.onPartial = sink; return live })
        await coordinator.dictationKeyPressed()
        await coordinator.dictationKeyReleased()
        await coordinator.waitForIdle()
        XCTAssertTrue(inserter.inserted.isEmpty)          // final paste skipped — text was typed
        XCTAssertTrue(cleanup.calls.isEmpty)              // level forced to .none
        XCTAssertEqual(liveInserter.typedUpTo.last, "live text") // flushed the final transcript
        XCTAssertEqual(coordinator.lastResult?.cleanedText, "live text") // raw == typed
    }

    func testLiveTypeStillSavesHistoryAndLastResult() async throws {
        let history = try HistoryStore(inMemory: true)
        let live = MockLiveSession()
        let coordinator = DictationCoordinator(recorder: MockRecorder(), engine: MockEngine(),
                                               cleanup: MockCleanup(), inserter: MockInserter(),
                                               minimumHold: 0, history: history,
                                               liveTypeProvider: { true },
                                               liveInserter: MockLiveInserter(),
                                               liveSessionFactory: { sink in live.onPartial = sink; return live })
        await coordinator.dictationKeyPressed()
        await coordinator.dictationKeyReleased()
        await coordinator.waitForIdle()
        XCTAssertEqual(history.recent(limit: 1)[0].status, .completed)
        XCTAssertNotNil(coordinator.lastResult)
        XCTAssertNotNil(coordinator.lastCompletedAt)
    }

    func testLiveTypeOffUsesNormalInsert() async {
        let live = MockLiveSession()
        let inserter = MockInserter()
        let coordinator = DictationCoordinator(recorder: MockRecorder(), engine: MockEngine(),
                                               cleanup: MockCleanup(), inserter: inserter, minimumHold: 0,
                                               liveTypeProvider: { false },
                                               liveInserter: MockLiveInserter(),
                                               liveSessionFactory: { sink in live.onPartial = sink; return live })
        await coordinator.dictationKeyPressed()
        await coordinator.dictationKeyReleased()
        await coordinator.waitForIdle()
        XCTAssertEqual(inserter.inserted, ["Clean text."]) // normal cleanup + paste
    }

    func testLiveTypeBatchFallbackPastesBatchResult() async {
        let live = MockLiveSession()
        live.finishResult = .failure(EngineError.requestFailed(status: 0, message: "socket died"))
        let inserter = MockInserter()
        // MockEngine returns "raw text"; live typing was on but realtime failed, so the
        // batch result must still be pasted (not skipped).
        let coordinator = DictationCoordinator(recorder: MockRecorder(), engine: MockEngine(),
                                               cleanup: MockCleanup(), inserter: inserter, minimumHold: 0,
                                               instantSkipCleanupProvider: { true }, // skip-cleanup → deliver raw batch result
                                               liveTypeProvider: { true },
                                               liveInserter: MockLiveInserter(),
                                               liveSessionFactory: { sink in live.onPartial = sink; return live })
        await coordinator.dictationKeyPressed()
        await coordinator.dictationKeyReleased()
        await coordinator.waitForIdle()
        XCTAssertEqual(inserter.inserted, ["raw text"]) // batch raw delivered (level forced .none)
    }

    func testLiveTypeFallsBackToInsertWhenNotViable() async {
        let live = MockLiveSession()
        let liveInserter = MockLiveInserter()
        liveInserter.viable = false // e.g. Accessibility not trusted
        let inserter = MockInserter()
        let coordinator = DictationCoordinator(recorder: MockRecorder(), engine: MockEngine(),
                                               cleanup: MockCleanup(), inserter: inserter, minimumHold: 0,
                                               instantSkipCleanupProvider: { true }, // skip-cleanup → keep raw live text
                                               liveTypeProvider: { true },
                                               liveInserter: liveInserter,
                                               liveSessionFactory: { sink in live.onPartial = sink; return live })
        await coordinator.dictationKeyPressed()
        await coordinator.dictationKeyReleased()
        await coordinator.waitForIdle()
        XCTAssertEqual(inserter.inserted, ["live text"]) // AX bail → normal insert of raw text
    }

    func testLiveTypeWithCleanupErasesTypedAndInsertsCleaned() async {
        // Live Typing + cleanup ON (skip-cleanup off): type raw live, then on release
        // erase what was typed and replace it with the cleaned text (erase-and-replace).
        let live = MockLiveSession()
        let liveInserter = MockLiveInserter()
        let cleanup = MockCleanup() // returns "Clean text."
        let inserter = MockInserter()
        let coordinator = DictationCoordinator(recorder: MockRecorder(), engine: MockEngine(),
                                               cleanup: cleanup, inserter: inserter, minimumHold: 0,
                                               cleanupLevelProvider: { .medium },
                                               instantSkipCleanupProvider: { false }, // cleanup ON → erase & replace
                                               liveTypeProvider: { true },
                                               liveInserter: liveInserter,
                                               liveSessionFactory: { sink in live.onPartial = sink; return live })
        await coordinator.dictationKeyPressed()
        await coordinator.dictationKeyReleased()
        await coordinator.waitForIdle()
        XCTAssertEqual(cleanup.calls.count, 1)              // cleanup ran (not skipped)
        XCTAssertEqual(liveInserter.eraseCount, 1)          // live-typed raw erased
        XCTAssertEqual(inserter.inserted, ["Clean text."])  // replaced with cleaned text
        XCTAssertEqual(coordinator.lastResult?.cleanedText, "Clean text.")
    }

    func testLiveTypingPausesWhenFocusLeavesPressTimeTarget() async {
        // Focus is stolen mid-dictation (e.g. Finder grabs it). Live typing must NOT
        // fire keystrokes into the new frontmost app — only the press-time target.
        let live = MockLiveSession()
        let liveInserter = MockLiveInserter()
        var frontmost: (bundleID: String?, name: String?) = ("com.target.app", "Target")
        let coordinator = DictationCoordinator(recorder: MockRecorder(), engine: MockEngine(),
                                               cleanup: MockCleanup(), inserter: MockInserter(), minimumHold: 0,
                                               frontmostApp: { frontmost },
                                               liveTypeProvider: { true },
                                               liveInserter: liveInserter,
                                               liveSessionFactory: { sink in live.onPartial = sink; return live })
        await coordinator.dictationKeyPressed()   // snapshots target = com.target.app
        frontmost = ("com.apple.finder", "Finder") // focus stolen away
        live.emit("stolen text")
        await waitForLive(coordinator, toEqual: "stolen text") // pump processed this value
        XCTAssertEqual(coordinator.liveTranscript, "stolen text") // preview keeps updating
        XCTAssertFalse(liveInserter.typedUpTo.contains("stolen text"),
                       "live typing must not target an app other than the press-time target")
        coordinator.cancel()
    }

    func testLiveTypingResumesWhenFocusReturnsToTarget() async {
        let live = MockLiveSession()
        let liveInserter = MockLiveInserter()
        var frontmost: (bundleID: String?, name: String?) = ("com.target.app", "Target")
        let coordinator = DictationCoordinator(recorder: MockRecorder(), engine: MockEngine(),
                                               cleanup: MockCleanup(), inserter: MockInserter(), minimumHold: 0,
                                               frontmostApp: { frontmost },
                                               liveTypeProvider: { true },
                                               liveInserter: liveInserter,
                                               liveSessionFactory: { sink in live.onPartial = sink; return live })
        await coordinator.dictationKeyPressed()
        frontmost = ("com.apple.finder", "Finder") // away
        live.emit("away")
        await waitForLive(coordinator, toEqual: "away")
        XCTAssertFalse(liveInserter.typedUpTo.contains("away")) // paused while away
        frontmost = ("com.target.app", "Target")   // focus returns to the target
        live.emit("away back")
        await waitForLive(coordinator, toEqual: "away back")
        XCTAssertEqual(liveInserter.typedUpTo.last, "away back") // typing resumed
        coordinator.cancel()
    }

    func testFinalDeliveryGoesToClipboardWhenFocusLeftTarget() async {
        // Focus switched away before release — the final insert must NOT paste into the
        // new frontmost app; it lands on the clipboard with a notification instead.
        var frontmost: (bundleID: String?, name: String?) = ("com.target.app", "Target")
        let inserter = MockInserter()
        let coordinator = DictationCoordinator(recorder: MockRecorder(), engine: MockEngine(),
                                               cleanup: MockCleanup(), inserter: inserter, minimumHold: 0,
                                               frontmostApp: { frontmost })
        await coordinator.dictationKeyPressed()    // targetApp = com.target.app
        frontmost = ("com.apple.finder", "Finder") // user switched apps mid-dictation
        await coordinator.dictationKeyReleased()
        await coordinator.waitForIdle()
        XCTAssertEqual(inserter.copied, ["Clean text."]) // clipboard fallback
        XCTAssertTrue(inserter.inserted.isEmpty)         // never pasted into Finder
        XCTAssertEqual(coordinator.state, .idle)
    }

    func testEraseFailureFallsBackToClipboardNotDuplicate() async {
        // Live typing + cleanup, but erase isn't viable (AX lost) — must NOT insert cleaned
        // on top of the raw (duplicate); falls back to the clipboard.
        let live = MockLiveSession()
        let liveInserter = MockLiveInserter()
        liveInserter.viable = false // type() and eraseTyped() both return false
        let inserter = MockInserter()
        let coordinator = DictationCoordinator(recorder: MockRecorder(), engine: MockEngine(),
                                               cleanup: MockCleanup(), inserter: inserter, minimumHold: 0,
                                               cleanupLevelProvider: { .medium },
                                               instantSkipCleanupProvider: { false },
                                               liveTypeProvider: { true },
                                               liveInserter: liveInserter,
                                               liveSessionFactory: { sink in live.onPartial = sink; return live })
        await coordinator.dictationKeyPressed()
        await coordinator.dictationKeyReleased()
        await coordinator.waitForIdle()
        XCTAssertEqual(liveInserter.eraseCount, 1)        // erase attempted
        XCTAssertEqual(inserter.copied, ["Clean text."])  // clipboard fallback, not insert
        XCTAssertTrue(inserter.inserted.isEmpty)          // no duplicate insert
    }

    // MARK: live transcript pump (Part B2)

    private func waitForLive(_ coordinator: DictationCoordinator, toEqual expected: String) async {
        for _ in 0..<50 { // up to ~1s, well past the 80ms pump
            if coordinator.liveTranscript == expected { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    func testLivePartialUpdatesLiveTranscript() async {
        let live = MockLiveSession()
        let coordinator = DictationCoordinator(recorder: MockRecorder(), engine: MockEngine(),
                                               cleanup: MockCleanup(), inserter: MockInserter(),
                                               minimumHold: 0,
                                               liveSessionFactory: { sink in live.onPartial = sink; return live })
        await coordinator.dictationKeyPressed()
        live.emit("hello")
        live.emit("hello world")
        await waitForLive(coordinator, toEqual: "hello world")
        XCTAssertEqual(coordinator.liveTranscript, "hello world") // last-write-wins
        await coordinator.dictationKeyReleased()
        await coordinator.waitForIdle()
    }

    func testLiveTranscriptResetsOnNextDictation() async {
        let live = MockLiveSession()
        let coordinator = DictationCoordinator(recorder: MockRecorder(), engine: MockEngine(),
                                               cleanup: MockCleanup(), inserter: MockInserter(),
                                               minimumHold: 0,
                                               liveSessionFactory: { sink in live.onPartial = sink; return live })
        await coordinator.dictationKeyPressed()
        live.emit("hello")
        await waitForLive(coordinator, toEqual: "hello")
        await coordinator.dictationKeyReleased()
        await coordinator.waitForIdle()
        await coordinator.dictationKeyPressed() // fresh dictation
        XCTAssertEqual(coordinator.liveTranscript, "") // reset immediately at press
        await coordinator.dictationKeyReleased()
        await coordinator.waitForIdle()
    }

    func testLiveTranscriptClearsOnCancel() async {
        let live = MockLiveSession()
        let coordinator = DictationCoordinator(recorder: MockRecorder(), engine: MockEngine(),
                                               cleanup: MockCleanup(), inserter: MockInserter(),
                                               minimumHold: 0,
                                               liveSessionFactory: { sink in live.onPartial = sink; return live })
        await coordinator.dictationKeyPressed()
        live.emit("hello")
        await waitForLive(coordinator, toEqual: "hello")
        coordinator.cancel()
        // next dictation start clears it; cancel stops the pump so it won't re-populate
        await coordinator.dictationKeyPressed()
        XCTAssertEqual(coordinator.liveTranscript, "")
        await coordinator.dictationKeyReleased()
        await coordinator.waitForIdle()
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
