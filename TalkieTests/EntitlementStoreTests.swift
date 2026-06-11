import XCTest
@testable import Talkie

@MainActor
final class EntitlementStoreTests: XCTestCase {
    private let keychain = KeychainStore(service: "com.archiev.talkie.entitlement.tests")

    override func tearDown() {
        keychain.delete(.licenseKey)
        keychain.delete(.trialSeal)
        super.tearDown()
    }

    private func makeStore(machineID: String = "A1B2C3D4",
                           now: @escaping () -> Date = Date.init) -> EntitlementStore {
        EntitlementStore(
            license: LicenseManager(keychain: keychain, machineIDProvider: { machineID }),
            trial: TrialManager(keychain: keychain, machineID: { machineID }, now: now))
    }

    func testFreshInstallIsExpiredUntilTrialStarts() {
        let store = makeStore()
        XCTAssertEqual(store.current, .expired)
        XCTAssertFalse(store.canDictate)
        XCTAssertFalse(store.trialHasStarted)
        XCTAssertEqual(store.gateError, .notStarted) // never-started ≠ expired
    }

    func testStartTrialGrantsFourteenDays() {
        let store = makeStore()
        store.startTrial()
        XCTAssertEqual(store.current, .trial(daysLeft: 14))
        XCTAssertTrue(store.canDictate)
        XCTAssertTrue(store.trialHasStarted)
        XCTAssertNil(store.gateError)
    }

    func testActivationBeatsTrial() {
        let store = makeStore()
        let key = LicenseKeyEncoder.encode(machineID: "A1B2C3D4", expiryDays: 36500)
        XCTAssertEqual(store.activate(key), .valid)
        XCTAssertEqual(store.current, .licensed)
        XCTAssertTrue(store.canDictate)
    }

    func testExpiredTrialBlocksDictation() {
        var current = Date()
        let store = makeStore(now: { current })
        store.startTrial()
        current = current.addingTimeInterval(20 * 86_400)
        store.refresh()
        XCTAssertEqual(store.current, .expired)
        XCTAssertFalse(store.canDictate)
        XCTAssertEqual(store.gateError, .expired)
    }
}
