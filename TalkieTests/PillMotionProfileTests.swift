import XCTest
@testable import Talkie

final class PillMotionProfileTests: XCTestCase {
    func testCalmFlowUsesBoundedSubtleScale() {
        let profile = PillMotionProfile.calmFlow

        XCTAssertEqual(profile.entryMinimumScale, 0.65, accuracy: 0.0001)
        XCTAssertEqual(profile.handsFreeMinimumScale, 0.985, accuracy: 0.0001)
        XCTAssertEqual(profile.handsFreeMaximumScale, 1.015, accuracy: 0.0001)
        XCTAssertEqual(profile.waveformFPS, 30)
        XCTAssertEqual(profile.successDuration, 0.8, accuracy: 0.0001)
    }

    func testReduceMotionKeepsGeometryStable() {
        let profile = PillMotionProfile.resolve(reduceMotion: true)

        XCTAssertEqual(profile.entryMinimumScale, 1)
        XCTAssertEqual(profile.handsFreeMinimumScale, 1)
        XCTAssertEqual(profile.handsFreeMaximumScale, 1)
        XCTAssertFalse(profile.animatesWaveformGeometry)
    }

    func testNormalMotionResolvesToCalmFlow() {
        XCTAssertEqual(PillMotionProfile.resolve(reduceMotion: false), .calmFlow)
    }
}
