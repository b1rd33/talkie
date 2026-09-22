import XCTest
@testable import Talkie

final class EngineRouterTests: XCTestCase {
    actor CallCounter {
        private var count = 0
        func record() { count += 1 }
        func value() -> Int { count }
    }

    struct CountingEngine: TranscriptionEngine {
        let counter: CallCounter
        var result: Result<Transcript, Error>
        func transcribe(_ audio: RecordedAudio, dictionaryTerms: [String],
                        onPartial: TranscriptionProgressSink?) async throws -> Transcript {
            await counter.record()
            return try result.get()
        }
    }

    private let audio = RecordedAudio(fileURL: URL(fileURLWithPath: "/tmp/x.m4a"), duration: 1)

    func testCloudModesUseCloudAndLegacyLocalNeverCallsIt() async throws {
        for mode in ["cloud", "instant", "local"] {
            let calls = CallCounter()
            let router = EngineRouter(cloud: CountingEngine(
                counter: calls, result: .success(Transcript(text: "cloud"))), mode: { mode })
            do {
                let transcript = try await router.transcribe(audio, dictionaryTerms: [])
                XCTAssertNotEqual(mode, "local")
                XCTAssertEqual(transcript.text, "cloud")
            } catch {
                XCTAssertEqual(mode, "local")
                XCTAssertEqual(error as? EngineError, .localTranscriptionRemoved)
            }
            let count = await calls.value()
            XCTAssertEqual(count, mode == "local" ? 0 : 1)
        }
    }

    func testCloudErrorsPropagateWithoutLocalFallback() async {
        for error in [EngineError.offline, .requestFailed(status: 503, message: "down"),
                      .requestFailed(status: 401, message: "bad key")] {
            let calls = CallCounter()
            let router = EngineRouter(cloud: CountingEngine(
                counter: calls, result: .failure(error)), mode: { "cloud" })
            do {
                _ = try await router.transcribe(audio, dictionaryTerms: [])
                XCTFail("Expected provider error")
            } catch let actual {
                XCTAssertEqual(actual as? EngineError, error)
            }
            let count = await calls.value()
            XCTAssertEqual(count, 1)
        }
    }
}
