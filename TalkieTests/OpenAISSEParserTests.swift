import XCTest
@testable import Talkie

final class OpenAISSEParserTests: XCTestCase {
    func testParsesFragmentedDeltaAndDoneEvents() throws {
        var parser = OpenAISSEParser()

        XCTAssertEqual(
            try parser.append(
                Data("data: {\"type\":\"transcript.text.del".utf8)),
            [])
        let events = try parser.append(Data(
            """
            ta","delta":"Hel"}

            data: {"type":"transcript.text.done","text":"Hello","languages":[{"code":"en"}]}


            """.utf8))

        XCTAssertEqual(events, [
            .delta("Hel"),
            .done(text: "Hello", detectedLanguages: ["en"]),
        ])
    }

    func testRejectsDoneEventWithoutText() {
        var parser = OpenAISSEParser()

        XCTAssertThrowsError(try parser.append(
            Data("data: {\"type\":\"transcript.text.done\"}\n\n".utf8)))
    }

    func testParsesCRLFDelimitedEvents() throws {
        var parser = OpenAISSEParser()

        let events = try parser.append(Data(
            "data: {\"type\":\"transcript.text.delta\",\"delta\":\"Hi\"}\r\n\r\n"
                .utf8))

        XCTAssertEqual(events, [.delta("Hi")])
    }

    func testIgnoresDoneSentinelAfterFinalTranscript() throws {
        var parser = OpenAISSEParser()

        let events = try parser.append(Data(
            """
            data: {"type":"transcript.text.done","text":"Hello","languages":[{"code":"en"}]}

            data: [DONE]


            """.utf8))

        XCTAssertEqual(
            events,
            [.done(text: "Hello", detectedLanguages: ["en"])])
    }
}
