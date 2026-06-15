import XCTest
@testable import Talkie

@MainActor
final class FnKeyMonitorTests: XCTestCase {
    private var presses = 0
    private var releases = 0
    private var monitor: FnKeyMonitor!

    override func setUp() async throws {
        presses = 0
        releases = 0
        monitor = FnKeyMonitor()
        monitor.onPress = { [weak self] in self?.presses += 1 }
        monitor.onRelease = { [weak self] in self?.releases += 1 }
    }

    func testPressThenRelease() {
        monitor.handleFlagsChanged(fnDown: true)
        monitor.handleFlagsChanged(fnDown: false)
        XCTAssertEqual(presses, 1)
        XCTAssertEqual(releases, 1)
    }

    func testRepeatedDownEventsFireOnce() {
        monitor.handleFlagsChanged(fnDown: true)
        monitor.handleFlagsChanged(fnDown: true) // e.g. fn+arrow also delivers flagsChanged
        XCTAssertEqual(presses, 1)
    }

    func testReleaseWithoutPressIgnored() {
        monitor.handleFlagsChanged(fnDown: false)
        XCTAssertEqual(releases, 0)
    }

    func testDoubleTapFires() {
        var doubleTaps = 0
        monitor.onDoubleTap = { doubleTaps += 1 }
        let t0 = Date()
        monitor.handleFlagsChanged(fnDown: true, at: t0)
        monitor.handleFlagsChanged(fnDown: false, at: t0.addingTimeInterval(0.1))  // tap 1
        monitor.handleFlagsChanged(fnDown: true, at: t0.addingTimeInterval(0.25))
        monitor.handleFlagsChanged(fnDown: false, at: t0.addingTimeInterval(0.35)) // tap 2
        XCTAssertEqual(doubleTaps, 1)
    }

    func testSlowTapsDoNotFireDoubleTap() {
        var doubleTaps = 0
        monitor.onDoubleTap = { doubleTaps += 1 }
        let t0 = Date()
        monitor.handleFlagsChanged(fnDown: true, at: t0)
        monitor.handleFlagsChanged(fnDown: false, at: t0.addingTimeInterval(0.1))
        monitor.handleFlagsChanged(fnDown: true, at: t0.addingTimeInterval(1.0)) // too late
        monitor.handleFlagsChanged(fnDown: false, at: t0.addingTimeInterval(1.1))
        XCTAssertEqual(doubleTaps, 0)
    }

    // MARK: startup replay priming (phantom launch dictation, 2026-06)

    func testStartupPrimedWhileFnDownIgnoresUntilNeutral() {
        // fn read as already down when monitoring starts → the replayed down and
        // the following release are startup noise and must fire nothing.
        let t0 = Date()
        monitor.primeStartupState(fnDown: true, at: t0)
        monitor.handleFlagsChanged(fnDown: true, at: t0.addingTimeInterval(0.01))  // stale replay
        monitor.handleFlagsChanged(fnDown: false, at: t0.addingTimeInterval(0.02)) // settles to neutral
        XCTAssertEqual(presses, 0)
        XCTAssertEqual(releases, 0)

        // A genuine press past the startup grace window works normally.
        monitor.handleFlagsChanged(fnDown: true, at: t0.addingTimeInterval(1.0))
        monitor.handleFlagsChanged(fnDown: false, at: t0.addingTimeInterval(1.1))
        XCTAssertEqual(presses, 1)
        XCTAssertEqual(releases, 1)
    }

    func testStartupPrimedNeutralPreservesBehavior() {
        // A press well past the startup grace window fires normally.
        let t0 = Date()
        monitor.primeStartupState(fnDown: false, at: t0)
        monitor.handleFlagsChanged(fnDown: true, at: t0.addingTimeInterval(1.0))
        monitor.handleFlagsChanged(fnDown: false, at: t0.addingTimeInterval(1.1))
        XCTAssertEqual(presses, 1)
        XCTAssertEqual(releases, 1)
    }

    func testStartupGraceWindowSwallowsReplayedPress() {
        // fn read as neutral at start, but a stray .function replay lands within
        // the grace window — it (and its release) must fire nothing.
        let t0 = Date()
        monitor.primeStartupState(fnDown: false, at: t0)
        monitor.handleFlagsChanged(fnDown: true, at: t0.addingTimeInterval(0.05))
        monitor.handleFlagsChanged(fnDown: false, at: t0.addingTimeInterval(0.15))
        XCTAssertEqual(presses, 0)
        XCTAssertEqual(releases, 0)

        // A genuine press after the grace window works.
        monitor.handleFlagsChanged(fnDown: true, at: t0.addingTimeInterval(1.0))
        monitor.handleFlagsChanged(fnDown: false, at: t0.addingTimeInterval(1.1))
        XCTAssertEqual(presses, 1)
        XCTAssertEqual(releases, 1)
    }

    func testIgnoredStartupReleaseDoesNotSeedDoubleTap() {
        var doubleTaps = 0
        monitor.onDoubleTap = { doubleTaps += 1 }
        let t0 = Date()
        monitor.primeStartupState(fnDown: true)
        monitor.handleFlagsChanged(fnDown: false, at: t0) // consumed neutral, not a tap
        // A single real tap right after must not pair with the consumed release.
        monitor.handleFlagsChanged(fnDown: true, at: t0.addingTimeInterval(0.05))
        monitor.handleFlagsChanged(fnDown: false, at: t0.addingTimeInterval(0.15))
        XCTAssertEqual(doubleTaps, 0)
    }
}
