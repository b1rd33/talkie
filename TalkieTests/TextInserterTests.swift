import XCTest
@testable import Talkie

@MainActor
final class TextInserterTests: XCTestCase {
    func testWritesTextToPasteboard() async throws {
        var postedPaste = false
        let inserter = TextInserter(pasteKeystroke: { postedPaste = true })
        try await inserter.insert("Hello from Talkie")
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "Hello from Talkie")
        XCTAssertTrue(postedPaste)
    }

    func testEmptyTextDoesNothing() async throws {
        var postedPaste = false
        let inserter = TextInserter(pasteKeystroke: { postedPaste = true })
        try await inserter.insert("   ")
        XCTAssertFalse(postedPaste)
    }
}
