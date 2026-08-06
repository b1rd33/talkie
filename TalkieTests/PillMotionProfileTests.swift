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
        XCTAssertEqual(profile.processingRotationDuration, 0.9, accuracy: 0.0001)
        XCTAssertEqual(profile.successDuration, 0.16, accuracy: 0.0001)
        XCTAssertEqual(profile.completionPanelDuration, 0.18, accuracy: 0.0001)
    }

    func testReduceMotionKeepsGeometryStable() {
        let profile = PillMotionProfile.resolve(reduceMotion: true)

        XCTAssertEqual(profile.entryMinimumScale, 1)
        XCTAssertEqual(profile.handsFreeMinimumScale, 1)
        XCTAssertEqual(profile.handsFreeMaximumScale, 1)
        XCTAssertEqual(profile.processingRotationDuration, 1.8)
        XCTAssertEqual(profile.waveformFPS, 8)
        XCTAssertFalse(profile.animatesWaveformGeometry)
    }

    func testNormalMotionResolvesToCalmFlow() {
        XCTAssertEqual(PillMotionProfile.resolve(reduceMotion: false), .calmFlow)
    }

    func testProcessingRotationAdvancesContinuouslyThroughCycle() {
        let profile = PillMotionProfile.calmFlow

        XCTAssertEqual(profile.processingRotationDegrees(at: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(profile.processingRotationDegrees(at: 0.225), 90, accuracy: 0.0001)
        XCTAssertEqual(profile.processingRotationDegrees(at: 0.45), 180, accuracy: 0.0001)
        XCTAssertEqual(profile.processingRotationDegrees(at: 0.9), 0, accuracy: 0.0001)
        XCTAssertEqual(PillMotionProfile.minimalMotion.processingRotationDegrees(at: 0.45), 90,
                       accuracy: 0.0001)
    }

    func testReduceMotionSlowsButDoesNotFreezeFunctionalProgress() {
        let normal = PillMotionProfile.resolve(reduceMotion: false)
        let reduced = PillMotionProfile.resolve(reduceMotion: true)

        XCTAssertGreaterThan(reduced.processingRotationDuration,
                             normal.processingRotationDuration)
        XCTAssertGreaterThan(reduced.processingRotationDegrees(at: 0.45), 0)
    }
}
