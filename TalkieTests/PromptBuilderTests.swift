import XCTest
@testable import Talkie

final class PromptBuilderTests: XCTestCase {
    private func prompt(level: CleanupLevel = .high, style: StylePreset = .neutral,
                        terms: [String] = [], language: String? = nil) -> String {
        PromptBuilder().systemPrompt(level: level, style: style,
                                     dictionaryTerms: terms, pinnedLanguage: language)
    }

    // MARK: levels

    func testHighLevelContainsCoreRules() {
        let p = prompt(level: .high)
        XCTAssertTrue(p.contains("filler"))
        XCTAssertTrue(p.localizedCaseInsensitiveContains("scratch that"))
        XCTAssertTrue(p.localizedCaseInsensitiveContains("only the cleaned text"))
        XCTAssertTrue(p.localizedCaseInsensitiveContains("do not answer"))
        XCTAssertTrue(p.localizedCaseInsensitiveContains("lists"))
    }

    func testMediumRemovesFillersButNotSelfCorrections() {
        let p = prompt(level: .medium)
        XCTAssertTrue(p.contains("filler"))
        XCTAssertFalse(p.localizedCaseInsensitiveContains("scratch that"))
    }

    func testLightIsPunctuationOnly() {
        let p = prompt(level: .light)
        XCTAssertTrue(p.contains("punctuation"))
        XCTAssertFalse(p.contains("filler"))
        XCTAssertTrue(p.localizedCaseInsensitiveContains("keep every word"))
    }

    func testNoneMatchesLightDefensively() {
        // The coordinator never calls cleanup at .none (Task 4); if someone does,
        // the builder behaves like .light rather than inventing a fifth prompt.
        XCTAssertEqual(prompt(level: .none), prompt(level: .light))
    }

    // MARK: styles

    func testNeutralStyleAddsNoStyleSection() {
        XCTAssertFalse(prompt(style: .neutral).contains("Style:"))
    }

    func testTechnicalStylePreservesIdentifiers() {
        let p = prompt(style: .technical)
        XCTAssertTrue(p.contains("camelCase"))
        XCTAssertTrue(p.contains("snake_case"))
        XCTAssertTrue(p.localizedCaseInsensitiveContains("ASCII quotes"))
    }

    func testCasualStyleAllowsContractions() {
        XCTAssertTrue(prompt(style: .casual).localizedCaseInsensitiveContains("contractions"))
    }

    func testPolishedStyleAsksForCompleteSentences() {
        XCTAssertTrue(prompt(style: .polished).localizedCaseInsensitiveContains("complete sentences"))
    }

    // MARK: dictionary

    func testDictionaryTermsInjected() {
        XCTAssertTrue(prompt(terms: ["Archiev", "Talkie"]).contains("Archiev, Talkie"))
    }

    func testNoDictionarySectionWhenEmpty() {
        XCTAssertFalse(prompt().contains("exact spellings"))
    }

    // MARK: language

    func testAutoLanguageKeepsSameLanguageRule() {
        XCTAssertTrue(prompt().localizedCaseInsensitiveContains("same language"))
    }

    func testPinnedLanguageOverridesSameLanguageRule() {
        let p = prompt(language: "German")
        XCTAssertTrue(p.contains("Write the output in German"))
        XCTAssertFalse(p.localizedCaseInsensitiveContains("same language as the transcript"))
    }
}
