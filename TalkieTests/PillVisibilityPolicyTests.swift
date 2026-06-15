import XCTest
@testable import Talkie

final class PillVisibilityPolicyTests: XCTestCase {
    // MARK: panel ordering

    func testMasterToggleOffNeverShows() {
        XCTAssertFalse(PillVisibilityPolicy.shouldShowPanel(
            state: .recording, style: .bareWaveform, showFlowBar: false, recentlyCompleted: false))
    }

    func testVisibleStylesStayVisibleWhenIdle() {
        for style in [PillStyle.bareWaveform, .dynamicIsland, .frostedGlass] {
            XCTAssertTrue(PillVisibilityPolicy.shouldShowPanel(
                state: .idle, style: style, showFlowBar: true, recentlyCompleted: false), "\(style)")
        }
    }

    func testHiddenOrdersOutWhenIdle() {
        // The crash trigger: an idle panel with nothing clickable must not exist at all.
        XCTAssertFalse(PillVisibilityPolicy.shouldShowPanel(
            state: .idle, style: .hidden, showFlowBar: true, recentlyCompleted: false))
    }

    func testHiddenShowsWhileActiveAndDuringCheckmarkFlash() {
        XCTAssertTrue(PillVisibilityPolicy.shouldShowPanel(
            state: .recording, style: .hidden, showFlowBar: true, recentlyCompleted: false))
        XCTAssertTrue(PillVisibilityPolicy.shouldShowPanel(
            state: .transcribing, style: .hidden, showFlowBar: true, recentlyCompleted: false))
        XCTAssertTrue(PillVisibilityPolicy.shouldShowPanel(
            state: .error("x"), style: .hidden, showFlowBar: true, recentlyCompleted: false))
        // ≤1s after a completed dictation the green checkmark still flashes
        XCTAssertTrue(PillVisibilityPolicy.shouldShowPanel(
            state: .idle, style: .hidden, showFlowBar: true, recentlyCompleted: true))
    }

    // MARK: mouse participation

    func testMouseIgnoredWhenIdleForAllStyles() {
        // The redesigned idle pill is a calm, click-through indicator: ignoring
        // mouse at idle also means AppKit never hit-tests it (crash-safe).
        for style in PillStyle.allCases {
            XCTAssertFalse(PillVisibilityPolicy.shouldAcceptMouse(state: .idle, style: style), "\(style)")
        }
    }

    func testMouseAcceptedWhileActiveForAllStyles() {
        for style in PillStyle.allCases {
            XCTAssertTrue(PillVisibilityPolicy.shouldAcceptMouse(state: .recording, style: style), "\(style)")
            XCTAssertTrue(PillVisibilityPolicy.shouldAcceptMouse(state: .cleaning, style: style), "\(style)")
        }
    }
}
