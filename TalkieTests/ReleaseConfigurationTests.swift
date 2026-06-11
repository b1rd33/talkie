import XCTest
@testable import Talkie

/// Verifies the shipped bundle's signing/config. Runs against the test HOST
/// app bundle — built from the same project.yml settings as the Release bundle.
final class ReleaseConfigurationTests: XCTestCase {
    private var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }

    /// codesign writes -d output to stderr; merge both streams.
    private func codesign(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = arguments + [Bundle.main.bundlePath]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    func testHardenedRuntimeIsEnabled() throws {
        let output = try codesign(["-dv"])
        XCTAssertTrue(output.contains("runtime"),
                      "hardened-runtime flag missing from code signature: \(output)")
    }

    func testEntitlementsAllowMicrophoneAndForbidSandbox() throws {
        let entitlements = try codesign(["-d", "--entitlements", "-", "--xml"])
        XCTAssertTrue(entitlements.contains("com.apple.security.device.audio-input"),
                      "audio-input entitlement missing — mic capture dies under hardened runtime")
        XCTAssertFalse(entitlements.contains("com.apple.security.app-sandbox"),
                       "sandbox must stay OFF — AX insertion is incompatible (see Talkie.entitlements)")
    }

    func testSparkleFeedConfiguration() throws {
        let feed = try XCTUnwrap(info["SUFeedURL"] as? String, "SUFeedURL missing from Info.plist")
        let url = try XCTUnwrap(URL(string: feed))
        XCTAssertEqual(url.scheme, "https", "Sparkle requires an HTTPS feed")
        XCTAssertEqual((feed as NSString).pathExtension, "xml")
        let publicKey = try XCTUnwrap(info["SUPublicEDKey"] as? String, "SUPublicEDKey missing")
        XCTAssertFalse(publicKey.isEmpty)
    }

    func testPlistMigrationKeepsMenuBarOnlyAndMicUsage() {
        XCTAssertEqual(info["LSUIElement"] as? Bool, true)
        XCTAssertEqual((info["NSMicrophoneUsageDescription"] as? String)?.isEmpty, false)
        XCTAssertEqual(info["CFBundleDisplayName"] as? String, "Talkie")
    }

    func testVersionIsReleaseSemver() {
        let version = info["CFBundleShortVersionString"] as? String ?? ""
        XCTAssertNotNil(version.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression),
                        "MARKETING_VERSION not set in project.yml (got '\(version)')")
    }
}
