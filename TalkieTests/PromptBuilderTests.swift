import XCTest
@testable import Talkie

final class PromptBuilderTests: XCTestCase {
    func testHighLevelPromptContainsCoreRules() {
        let prompt = PromptBuilder().systemPrompt(dictionaryTerms: [])
        XCTAssertTrue(prompt.contains("filler"))
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("scratch that"))
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("only the cleaned text"))
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("same language"))
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("do not answer"))
    }

    func testDictionaryTermsInjected() {
        let prompt = PromptBuilder().systemPrompt(dictionaryTerms: ["Archiev", "Talkie"])
        XCTAssertTrue(prompt.contains("Archiev, Talkie"))
    }

    func testNoDictionarySectionWhenEmpty() {
        let prompt = PromptBuilder().systemPrompt(dictionaryTerms: [])
        XCTAssertFalse(prompt.contains("exact spellings"))
    }
}
