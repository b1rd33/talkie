import XCTest
@testable import Talkie

final class SnippetProcessorTests: XCTestCase {
    func testNormalizationIsCaseInsensitiveAndCollapsesWhitespace() {
        XCTAssertEqual(SnippetProcessor.normalize("  My   Address  "), "my address")
    }

    func testWholePhraseMatchingDoesNotReplaceInsideWords() {
        let snippets = [SnippetExpansion(trigger: "addr", expansion: "42 Main St.")]

        let protected = SnippetProcessor.protect(
            "Use addr, not addressable.", snippets: snippets)

        XCTAssertEqual(protected.restore(protected.text),
                       "Use 42 Main St., not addressable.")
    }

    func testExpansionIsRestoredExactlyAfterCleanupChangesOtherText() throws {
        let snippets = [SnippetExpansion(trigger: "email signature",
                                         expansion: "Best,\nChristian — Talkie")]
        let protected = SnippetProcessor.protect(
            "hello email signature", snippets: snippets)
        let cleaned = protected.text.replacingOccurrences(of: "hello", with: "Hello!")

        XCTAssertEqual(protected.restore(cleaned),
                       "Hello! Best,\nChristian — Talkie")
    }

    @MainActor
    func testStoreRejectsDuplicateAndDictionaryCorrectionConflicts() throws {
        let history = try HistoryStore(inMemory: true)
        try history.addSnippet(trigger: "My Address", expansion: "42 Main St.")
        XCTAssertThrowsError(try history.addSnippet(trigger: " my   address ", expansion: "Other"))

        history.addTerm("Talkie", soundsLike: "talk e")
        XCTAssertThrowsError(try history.addSnippet(trigger: "Talk E", expansion: "Talkie"))
    }
}
