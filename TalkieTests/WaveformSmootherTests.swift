import XCTest
@testable import Talkie

final class WaveformSmootherTests: XCTestCase {
    func testRisesFasterThanItFalls() {
        var attack = WaveformSmoother(attack: 0.6, release: 0.1)
        var release = WaveformSmoother(attack: 0.6, release: 0.1)
        let rise = attack.update(target: 1.0)   // from 0 toward 1
        release.update(target: 1.0)             // prime high
        release.update(target: 1.0)
        release.update(target: 1.0)
        let fall = release.update(target: 0.0)  // from ~high toward 0
        // One attack step should move much closer to the target than one release step.
        XCTAssertGreaterThan(rise, 0.5)
        XCTAssertGreaterThan(fall, 0.5) // still high after a single release step
    }

    func testClampsToUnitRange() {
        var s = WaveformSmoother(attack: 1.0, release: 1.0)
        XCTAssertEqual(s.update(target: 5.0), 1.0, accuracy: 0.0001)
        XCTAssertEqual(s.update(target: -3.0), 0.0, accuracy: 0.0001)
    }

    func testConvergesTowardSteadyTarget() {
        var s = WaveformSmoother(attack: 0.5, release: 0.5)
        var v: Float = 0
        for _ in 0..<50 { v = s.update(target: 0.7) }
        XCTAssertEqual(v, 0.7, accuracy: 0.01)
    }
}
