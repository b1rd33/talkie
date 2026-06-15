import XCTest
@testable import Talkie

final class PillLayoutTests: XCTestCase {
    // The empirically observed screen from the bug report: logical 1800×1169,
    // visible frame inset by the menu bar at the top.
    private let screen = CGRect(x: 0, y: 0, width: 1800, height: 1132)
    private let size = CGSize(width: 260, height: 56)

    func testTopCenterIsHorizontallyCentered() {
        let origin = PillLayout.origin(position: "topCenter", panelSize: size,
                                       screenFrame: screen, margin: 12)
        // Bug evidence: panel sat at x=900 (midX) instead of midX - width/2.
        XCTAssertEqual(origin.x, 900 - 130) // 770
        XCTAssertEqual(origin.y, screen.maxY - 56 - 12)
    }

    func testBottomCenterIsHorizontallyCentered() {
        let origin = PillLayout.origin(position: "bottomCenter", panelSize: size,
                                       screenFrame: screen, margin: 12)
        XCTAssertEqual(origin.x, 770)
        XCTAssertEqual(origin.y, 12)
    }

    func testBottomLeftHugsTheLeadingEdge() {
        let origin = PillLayout.origin(position: "bottomLeft", panelSize: size,
                                       screenFrame: screen, margin: 12)
        XCTAssertEqual(origin.x, 12)
        XCTAssertEqual(origin.y, 12)
    }

    func testBottomRightAccountsForPanelWidth() {
        let origin = PillLayout.origin(position: "bottomRight", panelSize: size,
                                       screenFrame: screen, margin: 12)
        XCTAssertEqual(origin.x, 1800 - 260 - 12)
        XCTAssertEqual(origin.y, 12)
    }

    func testUnknownPositionFallsBackToBottomCenter() {
        let fallback = PillLayout.origin(position: "garbage", panelSize: size,
                                         screenFrame: screen, margin: 12)
        let bottomCenter = PillLayout.origin(position: "bottomCenter", panelSize: size,
                                             screenFrame: screen, margin: 12)
        XCTAssertEqual(fallback, bottomCenter)
    }

    func testRespectsVisibleFrameOffsets() {
        // Dock on the left + menu bar: visibleFrame does not start at (0, 0).
        let inset = CGRect(x: 70, y: 80, width: 1730, height: 1052)
        let origin = PillLayout.origin(position: "topCenter", panelSize: size,
                                       screenFrame: inset, margin: 12)
        XCTAssertEqual(origin.x, inset.midX - 130)
        XCTAssertEqual(origin.y, inset.maxY - 56 - 12)
    }

    func testDynamicIslandForcesTopCenterRegardlessOfRequest() {
        for requested in ["bottomCenter", "bottomLeft", "bottomRight", "topCenter"] {
            XCTAssertEqual(PillLayout.effectivePosition(style: .dynamicIsland, requested: requested),
                           "topCenter", requested)
        }
    }

    func testOtherStylesHonorRequestedPosition() {
        for style in [PillStyle.bareWaveform, .frostedGlass, .hidden] {
            XCTAssertEqual(PillLayout.effectivePosition(style: style, requested: "bottomLeft"), "bottomLeft")
        }
    }

    func testPanelSizeConstantMatchesTheDesignedPill() {
        // reposition() must never read the live panel frame (it can be zero
        // mid-refreshStyle); this constant is the single source of truth.
        XCTAssertEqual(PillLayout.panelSize, CGSize(width: 260, height: 56))
    }
}
