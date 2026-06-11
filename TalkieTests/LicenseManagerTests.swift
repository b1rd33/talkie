import XCTest
@testable import Talkie

@MainActor
final class LicenseManagerTests: XCTestCase {
    // Separate service so tests never touch a real license.
    private let keychain = KeychainStore(service: "com.archiev.talkie.license.tests")

    override func tearDown() {
        keychain.delete(.licenseKey)
        super.tearDown()
    }

    private func makeManager(machineID: String = "A1B2C3D4") -> LicenseManager {
        LicenseManager(keychain: keychain, machineIDProvider: { machineID })
    }

    /// Mints a key with the PRODUCTION secret (defaults), exactly like the keygen tool.
    private func validKey(machineID: String = "A1B2C3D4", days: Int = 36500) -> String {
        LicenseKeyEncoder.encode(machineID: machineID, expiryDays: days)
    }

    func testActivateValidKeyLicenses() {
        let manager = makeManager()
        XCTAssertEqual(manager.activateLicense(keyString: validKey()), .valid)
        XCTAssertTrue(manager.isLicensed)
        XCTAssertEqual(manager.currentLicense?.machineID, "A1B2C3D4")
        XCTAssertEqual(manager.currentLicense?.isExpired, false)
    }

    func testWrongMachineRejected() {
        let manager = makeManager(machineID: "DEADBEEF")
        XCTAssertEqual(manager.activateLicense(keyString: validKey(machineID: "A1B2C3D4")), .machineMismatch)
        XCTAssertFalse(manager.isLicensed)
    }

    func testExpiredKeyRejected() {
        let manager = makeManager()
        // expiryDays 10 = 2024-01-11, long past — signature is valid, date is not.
        XCTAssertEqual(manager.activateLicense(keyString: validKey(days: 10)), .expired)
        XCTAssertFalse(manager.isLicensed)
    }

    func testGarbageKeyRejected() {
        let manager = makeManager()
        XCTAssertEqual(manager.activateLicense(keyString: "NOT-A-KEY"), .invalidSignature)
        XCTAssertFalse(manager.isLicensed)
    }

    func testLicensePersistsAcrossInstances() {
        _ = makeManager().activateLicense(keyString: validKey())
        let second = makeManager() // loads + re-validates from Keychain in init
        XCTAssertTrue(second.isLicensed)
        XCTAssertEqual(second.validationResult, .valid)
    }

    func testClearLicense() {
        let manager = makeManager()
        _ = manager.activateLicense(keyString: validKey())
        manager.clearLicense()
        XCTAssertFalse(manager.isLicensed)
        XCTAssertEqual(manager.validationResult, .notFound)
        XCTAssertFalse(makeManager().isLicensed) // gone from Keychain too
    }
}
