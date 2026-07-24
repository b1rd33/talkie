import Foundation
import XCTest

final class HostIntegrationSafetyTests: XCTestCase {
    func testHostScriptUsesPerRunTokenAndMarkerInsteadOfFixedSentinel() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let script = try String(
            contentsOf: root.appendingPathComponent("scripts/host-integration.sh"),
            encoding: .utf8)

        XCTAssertTrue(script.contains("mktemp"))
        XCTAssertTrue(script.contains("TALKIE_HOST_INTEGRATION_TOKEN"))
        XCTAssertTrue(script.contains("TALKIE_HOST_INTEGRATION_MARKER"))
        let legacyMarker = "/tmp/talkie-host-integration." + "enabled"
        let legacyFlag = "TALKIE_RUN_" + "HOST_INTEGRATION"
        XCTAssertFalse(script.contains(legacyMarker))
        XCTAssertFalse(script.contains(legacyFlag))
    }
}
