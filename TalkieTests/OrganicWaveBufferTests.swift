import XCTest
@testable import Talkie

final class OrganicWaveBufferTests: XCTestCase {
    func testReducedMotionSamplesLevelWithoutAdvancingPhase() {
        let buffer = OrganicWaveBuffer(initialLevel: 0)

        buffer.advance(
            to: Date(timeIntervalSince1970: 1),
            level: 1,
            advancesPhase: false)

        XCTAssertGreaterThan(buffer.level, 0)
        XCTAssertEqual(buffer.frame, 0)
    }

    func testNormalMotionSamplesLevelAndAdvancesPhase() {
        let buffer = OrganicWaveBuffer(initialLevel: 0)

        buffer.advance(
            to: Date(timeIntervalSince1970: 1),
            level: 1,
            advancesPhase: true)

        XCTAssertGreaterThan(buffer.level, 0)
        XCTAssertEqual(buffer.frame, 1)
    }

    func testResetClearsStaleAmplitudePhaseAndTimestamp() {
        let date = Date(timeIntervalSince1970: 1)
        let buffer = OrganicWaveBuffer(initialLevel: 0.8)
        buffer.advance(to: date, level: 1)

        buffer.reset()

        XCTAssertEqual(buffer.level, 0)
        XCTAssertEqual(buffer.frame, 0)
        buffer.advance(to: date, level: 1)
        XCTAssertGreaterThan(buffer.level, 0)
        XCTAssertEqual(buffer.frame, 1)
    }
}
