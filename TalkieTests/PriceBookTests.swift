import XCTest
@testable import Talkie

final class PriceBookTests: XCTestCase {
    func testTranscriptionRates() {
        // 60s of audio at the known per-minute rates, no cleanup
        XCTAssertEqual(PriceBook.estimate(engine: "gpt-4o-mini-transcribe", durationSec: 60,
                                          cleanupModel: nil, wordCount: 0), 0.003, accuracy: 1e-9)
        XCTAssertEqual(PriceBook.estimate(engine: "realtime", durationSec: 60,
                                          cleanupModel: nil, wordCount: 0), 0.017, accuracy: 1e-9)
        XCTAssertEqual(PriceBook.estimate(engine: "mistralai/voxtral-mini-transcribe", durationSec: 60,
                                          cleanupModel: nil, wordCount: 0), 0.003, accuracy: 1e-9)
        XCTAssertEqual(PriceBook.estimate(engine: "microsoft/mai-transcribe-1.5", durationSec: 60,
                                          cleanupModel: nil, wordCount: 0), 0.006, accuracy: 1e-9)
    }

    func testLocalEngineIsFree() {
        XCTAssertEqual(PriceBook.estimate(engine: "parakeet", durationSec: 600,
                                          cleanupModel: nil, wordCount: 100), 0)
    }

    func testUnknownEngineUsesCheapCloudFallback() {
        // Legacy rows store engine "openai" without a model — assume mini pricing.
        XCTAssertEqual(PriceBook.estimate(engine: "openai", durationSec: 60,
                                          cleanupModel: nil, wordCount: 0), 0.003, accuracy: 1e-9)
    }

    func testCleanupCostAddsTokenEstimate() {
        // 1000 words ≈ 1400 tokens in + 1400 out on flash-lite (0.10/0.40 per M)
        let expected = 0.003 + (1400.0 / 1e6) * 0.10 + (1400.0 / 1e6) * 0.40
        XCTAssertEqual(PriceBook.estimate(engine: "gpt-4o-mini-transcribe", durationSec: 60,
                                          cleanupModel: "google/gemini-2.5-flash-lite",
                                          wordCount: 1000), expected, accuracy: 1e-9)
    }

    func testNilCleanupModelAddsNothing() {
        let asrOnly = PriceBook.estimate(engine: "gpt-4o-transcribe", durationSec: 30,
                                         cleanupModel: nil, wordCount: 500)
        XCTAssertEqual(asrOnly, 0.006 * 0.5, accuracy: 1e-9)
    }
}
