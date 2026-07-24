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

    func testBundleContainsCanonicalLicenseNotices() throws {
        let resources = try XCTUnwrap(Bundle.main.resourceURL)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: resources.appendingPathComponent("LICENSE").path),
            "Apache LICENSE must be included in the distributed app bundle"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: resources.appendingPathComponent("NOTICE").path),
            "Apache NOTICE must be included in the distributed app bundle"
        )

        let thirdPartyNoticeURL = resources.appendingPathComponent("THIRD_PARTY_NOTICES.txt")
        let notice = try String(contentsOf: thirdPartyNoticeURL, encoding: .utf8)
        XCTAssertEqual(
            notice,
            """
            Copyright (c) 2017–2019 Sam Soffes, http://soff.es

            Permission is hereby granted, free of charge, to any person obtaining
            a copy of this software and associated documentation files (the
            "Software"), to deal in the Software without restriction, including
            without limitation the rights to use, copy, modify, merge, publish,
            distribute, sublicense, and/or sell copies of the Software, and to
            permit persons to whom the Software is furnished to do so, subject to
            the following conditions:

            The above copyright notice and this permission notice shall be
            included in all copies or substantial portions of the Software.

            THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
            EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
            MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
            NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
            LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
            OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
            WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

            """
        )
    }
}
