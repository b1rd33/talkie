import XCTest
@testable import Talkie

final class CleanupServiceTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    private func makeService(apiKey: String? = "sk-or-test") -> CleanupService {
        CleanupService(apiKeyProvider: { apiKey }, modelProvider: { "google/gemini-2.5-flash" },
                       session: StubURLProtocol.session())
    }

    func testSendsChatRequestAndParsesContent() async throws {
        var captured: URLRequest?
        var capturedBody: Data?
        StubURLProtocol.handler = { request in
            captured = request
            capturedBody = request.httpBody ?? request.bodyStreamData()
            let body = #"{"choices": [{"message": {"role": "assistant", "content": "Hello, world."}}]}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200,
                                    httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        let cleaned = try await makeService().clean("um hello uh world", dictionaryTerms: [],
                                                    level: .high, style: .neutral, pinnedLanguage: nil)
        XCTAssertEqual(cleaned, "Hello, world.")

        let request = try XCTUnwrap(captured)
        XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-or-test")
        let json = try JSONSerialization.jsonObject(with: XCTUnwrap(capturedBody)) as! [String: Any]
        XCTAssertEqual(json["model"] as? String, "google/gemini-2.5-flash")
        let messages = json["messages"] as! [[String: Any]]
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["role"] as? String, "system")
        XCTAssertEqual(messages[1]["content"] as? String, "um hello uh world")
    }

    func testSystemPromptReflectsLevelStyleDictionaryAndLanguage() async throws {
        var capturedBody: Data?
        StubURLProtocol.handler = { request in
            capturedBody = request.httpBody ?? request.bodyStreamData()
            return (HTTPURLResponse(url: request.url!, statusCode: 200,
                                    httpVersion: nil, headerFields: nil)!,
                    Data(#"{"choices": [{"message": {"role": "assistant", "content": "ok"}}]}"#.utf8))
        }
        _ = try await makeService().clean("transcript", dictionaryTerms: ["Talkie"],
                                          level: .light, style: .technical, pinnedLanguage: "German")
        let json = try JSONSerialization.jsonObject(with: XCTUnwrap(capturedBody)) as! [String: Any]
        let system = (json["messages"] as! [[String: Any]])[0]["content"] as! String
        XCTAssertTrue(system.contains("camelCase"))                    // technical style
        XCTAssertFalse(system.contains("filler"))                      // light level
        XCTAssertTrue(system.contains("Write the output in German"))   // language pin
        XCTAssertTrue(system.contains("Talkie"))                       // dictionary
    }

    func testCustomEndpointAndExtraPayloadReachTheWire() async throws {
        // Direct-OpenAI provider: different endpoint, reasoning_effort merged into the body
        // (gpt-5-family models burn ~1.3s "thinking" without it).
        var captured: URLRequest?
        var capturedBody: Data?
        StubURLProtocol.handler = { request in
            captured = request
            capturedBody = request.httpBody ?? request.bodyStreamData()
            return (HTTPURLResponse(url: request.url!, statusCode: 200,
                                    httpVersion: nil, headerFields: nil)!,
                    Data(#"{"choices": [{"message": {"role": "assistant", "content": "ok"}}]}"#.utf8))
        }
        let service = CleanupService(
            apiKeyProvider: { "sk-test" }, modelProvider: { "gpt-5.4-nano" },
            endpointProvider: { URL(string: "https://api.openai.com/v1/chat/completions")! },
            extraPayloadProvider: { ["reasoning_effort": "none"] },
            session: StubURLProtocol.session())
        _ = try await service.clean("text", dictionaryTerms: [],
                                    level: .high, style: .neutral, pinnedLanguage: nil)
        XCTAssertEqual(try XCTUnwrap(captured).url?.absoluteString,
                       "https://api.openai.com/v1/chat/completions")
        let json = try JSONSerialization.jsonObject(with: XCTUnwrap(capturedBody)) as! [String: Any]
        XCTAssertEqual(json["model"] as? String, "gpt-5.4-nano")
        XCTAssertEqual(json["reasoning_effort"] as? String, "none")
    }

    func testMissingKeyThrows() async {
        do {
            _ = try await makeService(apiKey: nil).clean("text", dictionaryTerms: [],
                                                         level: .high, style: .neutral, pinnedLanguage: nil)
            XCTFail("expected throw")
        } catch let error as EngineError {
            XCTAssertEqual(error, .missingAPIKey)
        } catch { XCTFail("wrong error: \(error)") }
    }

    func testEmptyChoicesThrowsInvalidResponse() async {
        StubURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
             Data(#"{"choices": []}"#.utf8))
        }
        do {
            _ = try await makeService().clean("text", dictionaryTerms: [],
                                              level: .high, style: .neutral, pinnedLanguage: nil)
            XCTFail("expected throw")
        } catch let error as EngineError {
            XCTAssertEqual(error, .invalidResponse)
        } catch { XCTFail("wrong error: \(error)") }
    }
}
