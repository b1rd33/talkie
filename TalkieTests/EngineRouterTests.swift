import XCTest
@testable import Talkie

final class EngineRouterTests: XCTestCase {
    actor CallCounter {
        private var count = 0

        func record() { count += 1 }
        func value() -> Int { count }
    }

    struct StubEngine: TranscriptionEngine {
        var result: Result<Transcript, Error>
        func transcribe(
            _ audio: RecordedAudio,
            dictionaryTerms: [String],
            onPartial: TranscriptionProgressSink?
        ) async throws -> Transcript {
            try result.get()
        }
    }

    struct CountingEngine: TranscriptionEngine {
        let counter: CallCounter
        var result: Result<Transcript, Error>

        func transcribe(_ audio: RecordedAudio,
                        dictionaryTerms: [String],
                        onPartial: TranscriptionProgressSink?) async throws -> Transcript {
            await counter.record()
            return try result.get()
        }
    }

    private let audio = RecordedAudio(fileURL: URL(fileURLWithPath: "/tmp/x.m4a"), duration: 1)

    func testCloudModeUsesCloud() async throws {
        let router = EngineRouter(
            cloud: StubEngine(result: .success(Transcript(text: "cloud", engineID: "openai"))),
            local: StubEngine(result: .success(Transcript(text: "local", engineID: "parakeet"))),
            mode: { "cloud" }, localAvailable: { true })
        let t = try await router.transcribe(audio, dictionaryTerms: [])
        XCTAssertEqual(t.text, "cloud")
        XCTAssertFalse(t.usedFallback)
    }

    func testLocalModeUsesLocal() async throws {
        let router = EngineRouter(
            cloud: StubEngine(result: .success(Transcript(text: "cloud", engineID: "openai"))),
            local: StubEngine(result: .success(Transcript(text: "local", engineID: "parakeet"))),
            mode: { "local" }, localAvailable: { true })
        let t = try await router.transcribe(audio, dictionaryTerms: [])
        XCTAssertEqual(t.text, "local")
    }

    func testLocalModeWithoutModelsFailsClosedWithoutCallingCloud() async {
        let cloudCalls = CallCounter()
        let localCalls = CallCounter()
        let router = EngineRouter(
            cloud: CountingEngine(
                counter: cloudCalls,
                result: .success(Transcript(text: "cloud", engineID: "openai"))),
            local: CountingEngine(
                counter: localCalls,
                result: .success(Transcript(text: "local", engineID: "parakeet"))),
            mode: { "local" }, localAvailable: { false })

        do {
            _ = try await router.transcribe(audio, dictionaryTerms: [])
            XCTFail("local mode must fail closed when its models are unavailable")
        } catch {
            XCTAssertEqual(
                (error as? LocalizedError)?.errorDescription,
                "On-device models aren't downloaded. Download them in Settings → Engines, or explicitly switch to Cloud or Instant."
            )
        }
        let cloudCallCount = await cloudCalls.value()
        let localCallCount = await localCalls.value()
        XCTAssertEqual(cloudCallCount, 0)
        XCTAssertEqual(localCallCount, 0)
    }

    func testCloudOfflineFallsBackToLocal() async throws {
        let router = EngineRouter(
            cloud: StubEngine(result: .failure(EngineError.offline)),
            local: StubEngine(result: .success(Transcript(text: "local", engineID: "parakeet"))),
            mode: { "cloud" }, localAvailable: { true })
        let t = try await router.transcribe(audio, dictionaryTerms: [])
        XCTAssertEqual(t.text, "local")
        XCTAssertTrue(t.usedFallback)
    }

    func testCloudOfflineWithoutLocalRethrows() async {
        let router = EngineRouter(
            cloud: StubEngine(result: .failure(EngineError.offline)),
            local: StubEngine(result: .success(Transcript(text: "local", engineID: "parakeet"))),
            mode: { "cloud" }, localAvailable: { false })
        do {
            _ = try await router.transcribe(audio, dictionaryTerms: [])
            XCTFail("expected throw")
        } catch let error as EngineError {
            XCTAssertEqual(error, .offline)
        } catch { XCTFail("wrong error: \(error)") }
    }

    func testCloudServerErrorFallsBackToLocal() async throws {
        let router = EngineRouter(
            cloud: StubEngine(result: .failure(EngineError.requestFailed(status: 503, message: "upstream down"))),
            local: StubEngine(result: .success(Transcript(text: "local", engineID: "parakeet"))),
            mode: { "cloud" }, localAvailable: { true })
        let t = try await router.transcribe(audio, dictionaryTerms: [])
        XCTAssertEqual(t.text, "local")
        XCTAssertTrue(t.usedFallback)
    }

    func testCloudAuthErrorDoesNotFallBack() async {
        let router = EngineRouter(
            cloud: StubEngine(result: .failure(EngineError.requestFailed(status: 401, message: "bad key"))),
            local: StubEngine(result: .success(Transcript(text: "local", engineID: "parakeet"))),
            mode: { "cloud" }, localAvailable: { true })
        do {
            _ = try await router.transcribe(audio, dictionaryTerms: [])
            XCTFail("expected throw")
        } catch let error as EngineError {
            XCTAssertEqual(error, .requestFailed(status: 401, message: "bad key"))
        } catch { XCTFail("wrong error: \(error)") }
    }
}
