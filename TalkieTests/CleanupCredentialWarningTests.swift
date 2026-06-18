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

    // MARK: provider/model mispairing (silent cleanup degradation)

    func testOpenAIProviderWithOpenRouterStyleModelWarns() {
        // openai/gpt-5.4-nano is the OpenRouter-routed name; sent to OpenAI's API it
        // 404s and cleanup silently degrades to raw text.
        let msg = CleanupCredentialWarning.message(
            cleanupProvider: "openai", cleanupModel: "openai/gpt-5.4-nano",
            hasOpenAIKey: true, hasOpenRouterKey: true)
        XCTAssertNotNil(msg)
        XCTAssertTrue(msg!.contains("openai/gpt-5.4-nano"))
    }

    func testOpenRouterProviderWithOpenAIStyleModelWarns() {
        let msg = CleanupCredentialWarning.message(
            cleanupProvider: "openrouter", cleanupModel: "gpt-5.4-nano",
            hasOpenAIKey: true, hasOpenRouterKey: true)
        XCTAssertNotNil(msg)
        XCTAssertTrue(msg!.contains("gpt-5.4-nano"))
    }

    func testMatchedProviderAndModelAreSilent() {
        XCTAssertNil(CleanupCredentialWarning.message(
            cleanupProvider: "openai", cleanupModel: "gpt-5.4-nano",
            hasOpenAIKey: true, hasOpenRouterKey: true))
        XCTAssertNil(CleanupCredentialWarning.message(
            cleanupProvider: "openrouter", cleanupModel: "google/gemini-2.5-flash-lite",
            hasOpenAIKey: true, hasOpenRouterKey: true))
    }

    func testMissingKeyTakesPriorityOverMismatch() {
        let msg = CleanupCredentialWarning.message(
            cleanupProvider: "openai", cleanupModel: "openai/gpt-5.4-nano",
            hasOpenAIKey: false, hasOpenRouterKey: true)
        XCTAssertNotNil(msg)
        XCTAssertTrue(msg!.contains("no OpenAI key"))
    }

    func testEmptyModelDoesNotTriggerMismatch() {
        XCTAssertNil(CleanupCredentialWarning.message(
            cleanupProvider: "openai", cleanupModel: "",
            hasOpenAIKey: true, hasOpenRouterKey: true))
    }
}
