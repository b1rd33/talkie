import XCTest
@testable import Talkie

final class LLMSelectionTransformerTests: XCTestCase {
    override func tearDown() { StubURLProtocol.handler = nil; super.tearDown() }

    func testInstructionAndSelectionReachProviderAndOutputIsParsed() async throws {
        var body: Data?
        StubURLProtocol.handler = { request in
            body = request.httpBody ?? request.bodyStreamData()
            return (HTTPURLResponse(url: request.url!, statusCode: 200,
                                    httpVersion: nil, headerFields: nil)!,
                    Data(#"{"choices":[{"message":{"content":"Short result"}}]}"#.utf8))
        }
        let service = LLMSelectionTransformer(apiKeyProvider: { "key" },
            modelProvider: { "model" }, endpointProvider: { URL(string: "https://example.test")! },
            session: StubURLProtocol.session())
        let transformed = try await service.transform("Long original", instruction: "Make concise")
        XCTAssertEqual(transformed, "Short result")
        let json = try JSONSerialization.jsonObject(with: XCTUnwrap(body)) as! [String: Any]
        let messages = json["messages"] as! [[String: String]]
        XCTAssertTrue(messages[0]["content"]!.contains("Make concise"))
        XCTAssertEqual(messages[1]["content"], "Long original")
    }
}
