import XCTest
@testable import Talkie

@MainActor
final class DictationCoordinatorTests: XCTestCase {
    // MARK: mocks

    final class MockRecorder: AudioRecording {
        var latestLevel: Float = 0
        var started = 0
        var stopped = 0
        var discarded = 0
        var startError: Error?
        func start() async throws {
            started += 1
            if let startError { throw startError }
        }
        func stop() async throws -> RecordedAudio {
            stopped += 1
            return RecordedAudio(fileURL: URL(fileURLWithPath: "/tmp/fake.m4a"), duration: 2.0)
        }
        func discard() { discarded += 1 }
    }

    struct MockEngine: TranscriptionEngine {
        var result: Result<Transcript, Error> = .success(Transcript(text: "raw text"))
        func transcribe(_ audio: RecordedAudio, dictionaryTerms: [String]) async throws -> Transcript {
            try result.get()
        }
    }

    struct MockCleanup: CleanupServicing {
        var result: Result<String, Error> = .success("Clean text.")
        func clean(_ transcript: String, dictionaryTerms: [String]) async throws -> String {
            try result.get()
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
        inserter: MockInserter? = nil
    ) -> (DictationCoordinator, MockRecorder, MockInserter) {
        // Mocks conform to @MainActor protocols, so their inits can't run in
        // nonisolated default-argument position — construct them here instead.
        let recorder = recorder ?? MockRecorder()
        let inserter = inserter ?? MockInserter()
        let c = DictationCoordinator(recorder: recorder, engine: engine,
                                     cleanup: cleanup, inserter: inserter,
                                     minimumHold: 0) // disable debounce in most tests
        return (c, recorder, inserter)
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

    func testPressWhileProcessingIgnored() async {
        let (coordinator, recorder, _) = makeCoordinator()
        await coordinator.dictationKeyPressed()
        await coordinator.dictationKeyReleased() // processing starts
        await coordinator.dictationKeyPressed()  // spec §3: one dictation in flight
        await coordinator.waitForIdle()
        XCTAssertEqual(recorder.started, 1)
    }
}
