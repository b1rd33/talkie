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
}
