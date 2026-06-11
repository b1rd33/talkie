import XCTest
@testable import Talkie

final class TrialManagerTests: XCTestCase {
    private let keychain = KeychainStore(service: "com.archiev.talkie.license.tests")

    override func tearDown() {
        keychain.delete(.trialSeal)
        super.tearDown()
    }

    private func makeManager(machineID: String = "A1B2C3D4",
                             now: @escaping () -> Date = Date.init) -> TrialManager {
        TrialManager(keychain: keychain, machineID: { machineID }, now: now,
                     secret: "trial-test-secret")
    }

    func testNotStartedByDefault() {
        let trial = makeManager()
        XCTAssertFalse(trial.hasStarted)
        XCTAssertFalse(trial.isActive)
        XCTAssertEqual(trial.daysRemaining, 0)
    }

    func testStartGivesFourteenDays() {
        let trial = makeManager()
        trial.startTrial()
        XCTAssertTrue(trial.hasStarted)
        XCTAssertTrue(trial.isActive)
        XCTAssertEqual(trial.daysRemaining, 14)
    }

    func testCountsDownAndExpires() {
        var current = Date()
        let trial = makeManager(now: { current })
        trial.startTrial()
        current = current.addingTimeInterval(5 * 86_400)
        XCTAssertEqual(trial.daysRemaining, 9)
        current = current.addingTimeInterval(9 * 86_400) // day 14
        XCTAssertEqual(trial.daysRemaining, 0)
        XCTAssertFalse(trial.isActive)
        XCTAssertTrue(trial.hasStarted) // expired ≠ never started
    }

    func testClockRollbackExpires() {
        var current = Date()
        let trial = makeManager(now: { current })
        trial.startTrial()
        current = current.addingTimeInterval(-2 * 86_400) // user rolls the clock back
        XCTAssertTrue(trial.hasStarted)
        XCTAssertFalse(trial.isActive)
        XCTAssertEqual(trial.daysRemaining, 0)
    }

    func testTamperedSealTreatedAsNotStarted() {
        let trial = makeManager()
        trial.startTrial()
        // Hand-written far-future seal without a valid signature.
        keychain.write("A1B2C3D4|2099-01-01|deadbeef", for: .trialSeal)
        XCTAssertFalse(trial.hasStarted)
        XCTAssertEqual(trial.daysRemaining, 0)
    }

    func testSealFromAnotherMachineIgnored() {
        makeManager(machineID: "A1B2C3D4").startTrial()
        let other = makeManager(machineID: "DEADBEEF")
        XCTAssertFalse(other.hasStarted)
        XCTAssertFalse(other.isActive)
    }

    func testStartTwiceKeepsOriginalSeal() {
        var current = Date()
        let trial = makeManager(now: { current })
        trial.startTrial()
        let original = keychain.read(.trialSeal)
        current = current.addingTimeInterval(3 * 86_400)
        trial.startTrial() // must NOT reset the countdown
        XCTAssertEqual(keychain.read(.trialSeal), original)
        XCTAssertEqual(trial.daysRemaining, 11)
    }
}
