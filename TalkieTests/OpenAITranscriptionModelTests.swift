import XCTest
@testable import Talkie

final class OpenAITranscriptionModelTests: XCTestCase {
    func testRecommendedModelsExposeDocumentedCapabilities() {
        XCTAssertEqual(OpenAITranscriptionModel.gptTranscribe.workflow, .batch)
        XCTAssertTrue(OpenAITranscriptionModel.gptTranscribe.supportsKeywords)
        XCTAssertTrue(OpenAITranscriptionModel.gptTranscribe.supportsMultipleLanguages)
        XCTAssertTrue(OpenAITranscriptionModel.gptTranscribe.returnsDetectedLanguages)
        XCTAssertEqual(OpenAITranscriptionModel.gptTranscribe.pricePerMinute, 0.0045)

        XCTAssertEqual(OpenAITranscriptionModel.gptLiveTranscribe.workflow, .realtime)
        XCTAssertTrue(OpenAITranscriptionModel.gptLiveTranscribe.supportsDelay)
        XCTAssertFalse(OpenAITranscriptionModel.gptLiveTranscribe.returnsDetectedLanguages)
        XCTAssertEqual(OpenAITranscriptionModel.gptLiveTranscribe.pricePerMinute, 0.017)
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
