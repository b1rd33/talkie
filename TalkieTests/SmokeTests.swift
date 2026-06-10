import XCTest
@testable import Talkie

final class SmokeTests: XCTestCase {
    func testHarnessRuns() {
        XCTAssertTrue(AppDelegate.isRunningTests)
    }
}
