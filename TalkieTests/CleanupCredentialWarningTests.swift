import XCTest
@testable import Talkie

final class CleanupCredentialWarningTests: XCTestCase {
    func testOpenAIProviderWithoutKeyWarns() {
        let msg = CleanupCredentialWarning.message(
            cleanupProvider: "openai", hasOpenAIKey: false, hasOpenRouterKey: true)
        XCTAssertNotNil(msg)
        XCTAssertTrue(msg!.contains("OpenAI"))
    }

    func testOpenAIProviderWithKeyIsSilent() {
        XCTAssertNil(CleanupCredentialWarning.message(
            cleanupProvider: "openai", hasOpenAIKey: true, hasOpenRouterKey: false))
    }

    func testOpenRouterProviderWithoutKeyWarns() {
        let msg = CleanupCredentialWarning.message(
            cleanupProvider: "openrouter", hasOpenAIKey: true, hasOpenRouterKey: false)
        XCTAssertNotNil(msg)
        XCTAssertTrue(msg!.contains("OpenRouter"))
    }

    func testOpenRouterProviderWithKeyIsSilent() {
        XCTAssertNil(CleanupCredentialWarning.message(
            cleanupProvider: "openrouter", hasOpenAIKey: false, hasOpenRouterKey: true))
    }

    func testUnknownProviderTreatedAsOpenRouter() {
        XCTAssertNil(CleanupCredentialWarning.message(
            cleanupProvider: "something-else", hasOpenAIKey: false, hasOpenRouterKey: true))
    }
}
