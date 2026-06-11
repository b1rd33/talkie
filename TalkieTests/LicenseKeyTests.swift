import XCTest
@testable import Talkie

final class LicenseKeyTests: XCTestCase {
    private let testSecret = "test-secret-for-unit-tests"

    func testSecretDecodesToNonEmptyString() {
        XCTAssertFalse(LicenseSecret.value.isEmpty)
        XCTAssertTrue(LicenseSecret.value.hasPrefix("Talkie"))
    }

    func testRoundTripEncodeDecode() throws {
        let key = LicenseKeyEncoder.encode(machineID: "A1B2C3D4", expiryDays: 730, secret: testSecret)
        // Format: XXXXX-XXXXX-XXXXX-XXXXX (20 chars + 3 dashes)
        XCTAssertEqual(key.count, 23)
        XCTAssertEqual(key.filter { $0 == "-" }.count, 3)
        let decoded = try XCTUnwrap(LicenseKeyEncoder.decode(key, secret: testSecret))
        XCTAssertEqual(decoded.machineID, "A1B2C3D4")
        let base = DateComponents(calendar: .current, year: 2024, month: 1, day: 1).date!
        let expected = Calendar.current.date(byAdding: .day, value: 730, to: base)!
        XCTAssertEqual(decoded.expiryDate, expected)
    }

    func testTamperedSignatureRejected() {
        let key = LicenseKeyEncoder.encode(machineID: "A1B2C3D4", expiryDays: 730, secret: testSecret)
        // Flip the last signature character to a different alphabet character.
        var raw = key.replacingOccurrences(of: "-", with: "")
        let last = raw.removeLast()
        raw.append(last == "A" ? "B" : "A")
        XCTAssertNil(LicenseKeyEncoder.decode(raw, secret: testSecret))
    }

    func testWrongSecretRejected() {
        let key = LicenseKeyEncoder.encode(machineID: "A1B2C3D4", expiryDays: 730, secret: testSecret)
        XCTAssertNil(LicenseKeyEncoder.decode(key, secret: "another-secret"))
    }

    func testGarbageRejected() {
        XCTAssertNil(LicenseKeyEncoder.decode("HELLO", secret: testSecret))
        XCTAssertNil(LicenseKeyEncoder.decode("", secret: testSecret))
        XCTAssertNil(LicenseKeyEncoder.decode("AAAAA-AAAAA-AAAAA-AAAAA", secret: testSecret))
    }

    func testDashesAndLowercaseTolerated() throws {
        let key = LicenseKeyEncoder.encode(machineID: "EC8495C8", expiryDays: 36500, secret: testSecret)
        let decoded = try XCTUnwrap(LicenseKeyEncoder.decode(key.lowercased(), secret: testSecret))
        XCTAssertEqual(decoded.machineID, "EC8495C8")
    }
}
