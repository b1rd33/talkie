import XCTest
@testable import Talkie

final class OpenAIEngineTests: XCTestCase {
    private var audioURL: URL!

    override func setUpWithError() throws {
        audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("fake-\(UUID().uuidString).m4a")
        try Data("fake-audio".utf8).write(to: audioURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: audioURL)
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    private func makeEngine(apiKey: String? = "sk-test", model: String = "gpt-4o-mini-transcribe") -> OpenAIEngine {
        OpenAIEngine(apiKeyProvider: { apiKey }, modelProvider: { model },
                     session: StubURLProtocol.session())
    }

    func testSendsMultipartRequestAndParsesText() async throws {
        var captured: URLRequest?
        var capturedBody: Data?
        StubURLProtocol.handler = { request in
            captured = request
            capturedBody = request.httpBody ?? request.bodyStreamData()
            let body = #"{"text": "hello world"}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200,
                                    httpVersion: nil, headerFields: nil)!,
                    Data(body.utf8))
        }
        let result = try await makeEngine().transcribe(
            RecordedAudio(fileURL: audioURL, duration: 1.0), dictionaryTerms: ["Talkie"])

        XCTAssertEqual(result.text, "hello world")
        let request = try XCTUnwrap(captured)
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/audio/transcriptions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        let contentType = try XCTUnwrap(request.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary="))
        let body = try XCTUnwrap(capturedBody.flatMap { String(data: $0, encoding: .utf8) })
        XCTAssertTrue(body.contains("name=\"model\""))
        XCTAssertTrue(body.contains("gpt-4o-mini-transcribe"))
        XCTAssertTrue(body.contains("name=\"file\"; filename=\"audio.m4a\""))
        XCTAssertTrue(body.contains("name=\"prompt\""))
        XCTAssertTrue(body.contains("Talkie"))
        XCTAssertTrue(body.contains("fake-audio"))
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

    func testOfflineErrorMapsToOfflineCase() async {
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await makeEngine().transcribe(
                RecordedAudio(fileURL: audioURL, duration: 1.0), dictionaryTerms: [])
            XCTFail("expected throw")
        } catch let error as EngineError {
            XCTAssertEqual(error, .offline)
        } catch { XCTFail("wrong error: \(error)") }
    }

    func testHTTPErrorSurfacesStatusAndBody() async {
        StubURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!,
             Data(#"{"error": {"message": "bad key"}}"#.utf8))
        }
        do {
            _ = try await makeEngine().transcribe(
                RecordedAudio(fileURL: audioURL, duration: 1.0), dictionaryTerms: [])
            XCTFail("expected throw")
        } catch let error as EngineError {
            guard case .requestFailed(let status, let message) = error else {
                return XCTFail("wrong case: \(error)")
            }
            XCTAssertEqual(status, 401)
            XCTAssertTrue(message.contains("bad key"))
        } catch { XCTFail("wrong error: \(error)") }
    }
}
