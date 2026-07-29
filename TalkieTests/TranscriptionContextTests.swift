import XCTest
@testable import Talkie

final class TranscriptionContextTests: XCTestCase {
    func testNormalizesKeywordsAndLanguages() {
        let context = TranscriptionContext.build(
            prompt: "  A Talkie product demo.  ",
            dictionaryTerms: [" Talkie ", "talkie", "AC-42\r\nbilling", "<unsafe>"],
            languageCodes: ["en-US", "fr-CA", "zh-Hant", "bad value"])

        XCTAssertEqual(context.prompt, "A Talkie product demo.")
        XCTAssertEqual(context.keywords, ["Talkie", "AC-42 billing"])
        XCTAssertEqual(context.languages, ["en", "fr", "zh-tw"])
    }

    func testEmptyConfigurationStaysEmpty() {
        let context = TranscriptionContext.build(
            prompt: "",
            dictionaryTerms: [],
            languageCodes: [])

        XCTAssertNil(context.prompt)
        XCTAssertEqual(context.keywords, [])
        XCTAssertEqual(context.languages, [])
    }

    func testLegacyLanguageUsesFirstExpectedLanguage() {
        let context = TranscriptionContext(
            prompt: "Product demo",
            keywords: ["Talkie"],
            languages: ["en", "de"])

        XCTAssertEqual(context.legacyLanguage, "en")
    }

    func testDictionaryKeywordValidatorRejectsServerForbiddenCharacters() {
        XCTAssertThrowsError(try DictionaryKeywordValidator.validate("bad<term"))
        XCTAssertThrowsError(try DictionaryKeywordValidator.validate("two\nlines"))
        XCTAssertNoThrow(try DictionaryKeywordValidator.validate("C++"))
    }
}
