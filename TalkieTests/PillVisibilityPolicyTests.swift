import XCTest
@testable import Talkie

final class PillVisibilityPolicyTests: XCTestCase {
    // MARK: panel ordering

    func testMasterToggleOffNeverShows() {
        XCTAssertFalse(PillVisibilityPolicy.shouldShowPanel(
            state: .recording, style: "classic", showFlowBar: false, recentlyCompleted: false))
    }

    func testClassicAndDotStayVisibleWhenIdle() {
        for style in ["classic", "dot"] {
            XCTAssertTrue(PillVisibilityPolicy.shouldShowPanel(
                state: .idle, style: style, showFlowBar: true, recentlyCompleted: false), style)
        }
    }

    func testHiddenAndCompactOrderOutWhenIdle() {
        // The crash trigger: an idle panel with nothing clickable must not exist at all.
        for style in ["hidden", "compact"] {
            XCTAssertFalse(PillVisibilityPolicy.shouldShowPanel(
                state: .idle, style: style, showFlowBar: true, recentlyCompleted: false), style)
        }
    }

    func testHiddenShowsWhileActiveAndDuringCheckmarkFlash() {
        XCTAssertTrue(PillVisibilityPolicy.shouldShowPanel(
            state: .recording, style: "hidden", showFlowBar: true, recentlyCompleted: false))
        XCTAssertTrue(PillVisibilityPolicy.shouldShowPanel(
            state: .transcribing, style: "hidden", showFlowBar: true, recentlyCompleted: false))
        XCTAssertTrue(PillVisibilityPolicy.shouldShowPanel(
            state: .error("x"), style: "hidden", showFlowBar: true, recentlyCompleted: false))
        // ≤1s after a completed dictation the green checkmark still flashes
        XCTAssertTrue(PillVisibilityPolicy.shouldShowPanel(
            state: .idle, style: "hidden", showFlowBar: true, recentlyCompleted: true))
    }

    // MARK: mouse participation

    func testMouseIgnoredWhenIdleExceptClassic() {
        XCTAssertTrue(PillVisibilityPolicy.shouldAcceptMouse(state: .idle, style: "classic")) // hover mic + context menu
        for style in ["dot", "hidden", "compact"] {
            XCTAssertFalse(PillVisibilityPolicy.shouldAcceptMouse(state: .idle, style: style), style)
        }
    }

    func testMouseAcceptedWhileActiveForAllStyles() {
        for style in ["classic", "dot", "hidden", "compact"] {
            XCTAssertTrue(PillVisibilityPolicy.shouldAcceptMouse(state: .recording, style: style), style)
            XCTAssertTrue(PillVisibilityPolicy.shouldAcceptMouse(state: .cleaning, style: style), style)
        }
    }
}
