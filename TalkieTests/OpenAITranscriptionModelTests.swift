import XCTest
@testable import Talkie

final class OpenAITranscriptionModelTests: XCTestCase {
    func testRecommendedModelsExposeDocumentedCapabilities() {
        XCTAssertTrue(OpenAITranscriptionModel.gptTranscribe.supportsKeywords)

        XCTAssertTrue(OpenAITranscriptionModel.gptLiveTranscribe.supportsDelay)
    }

    func testLegacyModelsRemainAvailableButAreNotDefaults() {
        XCTAssertEqual(ModelPresets.openAIBatch.first, "gpt-transcribe")
        XCTAssertEqual(ModelPresets.openAIRealtime.first, "gpt-live-transcribe")
        XCTAssertTrue(ModelPresets.openAIBatch.contains("gpt-4o-mini-transcribe"))
        XCTAssertTrue(ModelPresets.openAIBatch.contains("gpt-4o-transcribe"))
        XCTAssertTrue(ModelPresets.openAIRealtime.contains("gpt-realtime-whisper"))
        XCTAssertTrue(OpenAITranscriptionModel.gpt4oMiniTranscribe.isLegacy)
    }
}
