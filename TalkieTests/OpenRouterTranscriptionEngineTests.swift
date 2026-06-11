import XCTest
@testable import Talkie

final class OpenRouterTranscriptionEngineTests: XCTestCase {
    private var audioURL: URL!

    override func setUpWithError() throws {
        audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("fake-or-\(UUID().uuidString).m4a")
        try Data("fake-audio-bytes".utf8).write(to: audioURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: audioURL)
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    private func makeEngine(apiKey: String? = "sk-or-test",
                            model: String = "mistralai/voxtral-mini-transcribe") -> OpenRouterTranscriptionEngine {
        OpenRouterTranscriptionEngine(apiKeyProvider: { apiKey }, modelProvider: { model },
                                      session: StubURLProtocol.session())
    }

    func testSendsJSONInputAudioAndParsesText() async throws {
        var captured: URLRequest?
        var capturedBody: Data?
        StubURLProtocol.handler = { request in
            captured = request
            capturedBody = request.httpBody ?? request.bodyStreamData()
            return (HTTPURLResponse(url: request.url!, statusCode: 200,
                                    httpVersion: nil, headerFields: nil)!,
                    Data(#"{"text": "hello from voxtral", "usage": {"cost": 0.0002}}"#.utf8))
        }
        let result = try await makeEngine().transcribe(
            RecordedAudio(fileURL: audioURL, duration: 2.0), dictionaryTerms: ["ignored"])

        XCTAssertEqual(result.text, "hello from voxtral")
        XCTAssertEqual(result.engineID, "mistralai/voxtral-mini-transcribe") // model id lands in History
        let request = try XCTUnwrap(captured)
        XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/audio/transcriptions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-or-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let json = try JSONSerialization.jsonObject(with: XCTUnwrap(capturedBody)) as! [String: Any]
        XCTAssertEqual(json["model"] as? String, "mistralai/voxtral-mini-transcribe")
        let inputAudio = try XCTUnwrap(json["input_audio"] as? [String: Any])
        XCTAssertEqual(inputAudio["format"] as? String, "m4a") // live-verified accepted format
        XCTAssertEqual(inputAudio["data"] as? String, Data("fake-audio-bytes".utf8).base64EncodedString())
    }

    func testMissingKeyThrows() async {
        do {
            _ = try await makeEngine(apiKey: nil).transcribe(
                RecordedAudio(fileURL: audioURL, duration: 1.0), dictionaryTerms: [])
            XCTFail("expected throw")
        } catch let error as EngineError {
            XCTAssertEqual(error, .missingAPIKey)
        } catch { XCTFail("wrong error: \(error)") }
    }

    func testHTTPErrorSurfaces() async {
        StubURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 402, httpVersion: nil, headerFields: nil)!,
             Data(#"{"error": {"message": "insufficient credits"}}"#.utf8))
        }
        do {
            _ = try await makeEngine().transcribe(
                RecordedAudio(fileURL: audioURL, duration: 1.0), dictionaryTerms: [])
            XCTFail("expected throw")
        } catch let error as EngineError {
            guard case .requestFailed(let status, let message) = error else {
                return XCTFail("wrong case: \(error)")
            }
            XCTAssertEqual(status, 402)
            XCTAssertTrue(message.contains("insufficient credits"))
        } catch { XCTFail("wrong error: \(error)") }
    }

    func testOfflineMapsToOffline() async {
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await makeEngine().transcribe(
                RecordedAudio(fileURL: audioURL, duration: 1.0), dictionaryTerms: [])
            XCTFail("expected throw")
        } catch let error as EngineError {
            XCTAssertEqual(error, .offline) // EngineRouter's local-fallback trigger
        } catch { XCTFail("wrong error: \(error)") }
    }
}
