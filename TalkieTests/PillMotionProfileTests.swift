import XCTest
@testable import Talkie

final class PillMotionProfileTests: XCTestCase {
    func testCalmFlowUsesBoundedSubtleScale() {
        let profile = PillMotionProfile.calmFlow

        XCTAssertEqual(profile.entryDuration, 0.18, accuracy: 0.0001)
        XCTAssertEqual(profile.entryMinimumScale, 0.92, accuracy: 0.0001)
        XCTAssertEqual(profile.handsFreeMinimumScale, 0.985, accuracy: 0.0001)
        XCTAssertEqual(profile.handsFreeMaximumScale, 1.015, accuracy: 0.0001)
        XCTAssertEqual(profile.waveformFPS, 30)
        XCTAssertEqual(profile.processingLabelDelay, 0.65, accuracy: 0.0001)
        XCTAssertEqual(profile.successDuration, 0.4, accuracy: 0.0001)
        XCTAssertEqual(profile.completionPanelDuration, 0.6, accuracy: 0.0001)
    }

    func testReduceMotionKeepsGeometryStable() {
        let profile = PillMotionProfile.resolve(reduceMotion: true)

        XCTAssertEqual(profile.entryMinimumScale, 1)
        XCTAssertEqual(profile.handsFreeMinimumScale, 1)
        XCTAssertEqual(profile.handsFreeMaximumScale, 1)
        XCTAssertEqual(profile.waveformFPS, 8)
        XCTAssertFalse(profile.animatesWaveformGeometry)
    }

    func testNormalMotionResolvesToCalmFlow() {
        XCTAssertEqual(PillMotionProfile.resolve(reduceMotion: false), .calmFlow)
    }
}
