import XCTest
@testable import Talkie

final class HomeStatsTests: XCTestCase {
    func testMinutesSavedSubtractsSpeakingTime() {
        // 450 words typed at 45wpm = 10 min; spoken in 2 min → 8 min saved
        XCTAssertEqual(HomeView.minutesSaved(words: 450, duration: 120), 8)
    }

    func testMinutesSavedNeverNegative() {
        XCTAssertEqual(HomeView.minutesSaved(words: 10, duration: 3600), 0)
    }

    func testZeroIsZero() {
        XCTAssertEqual(HomeView.minutesSaved(words: 0, duration: 0), 0)
    }
}
