import XCTest
@testable import Talkie

final class EngineRouterTests: XCTestCase {
    struct StubEngine: TranscriptionEngine {
        var result: Result<Transcript, Error>
        func transcribe(_ audio: RecordedAudio, dictionaryTerms: [String]) async throws -> Transcript {
            try result.get()
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

    func testLocalModeWithoutModelsFallsBackToCloud() async throws {
        let router = EngineRouter(
            cloud: StubEngine(result: .success(Transcript(text: "cloud", engineID: "openai"))),
            local: StubEngine(result: .failure(EngineError.invalidResponse)),
            mode: { "local" }, localAvailable: { false })
        let t = try await router.transcribe(audio, dictionaryTerms: [])
        XCTAssertEqual(t.text, "cloud")
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
