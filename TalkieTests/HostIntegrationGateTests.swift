import Darwin
import Foundation
import XCTest

final class HostIntegrationGateTests: XCTestCase {
    private let token = "test-host-integration-token-00000000"
    private let path = "/tmp/talkie-host-integration.test-token"
    private let userID = geteuid()
    private let now = Date(timeIntervalSince1970: 10_000)

    func testAllowsOnlyMatchingFreshOwnerOnlyRegularMarker() {
        let environment = validEnvironment()
        let valid = validMarker()

        XCTAssertTrue(HostIntegrationGate.allows(
            environment: environment,
            marker: valid,
            now: now,
            currentUserID: userID))

        var wrongToken = valid
        wrongToken.token = String(repeating: "x", count: token.count)
        XCTAssertFalse(HostIntegrationGate.allows(
            environment: environment,
            marker: wrongToken,
            now: now,
            currentUserID: userID))

        var wrongOwner = valid
        wrongOwner.ownerUserID = userID &+ 1
        XCTAssertFalse(HostIntegrationGate.allows(
            environment: environment,
            marker: wrongOwner,
            now: now,
            currentUserID: userID))

        var stale = valid
        stale.modifiedAt = now.addingTimeInterval(-HostIntegrationGate.maximumMarkerAge - 1)
        XCTAssertFalse(HostIntegrationGate.allows(
            environment: environment,
            marker: stale,
            now: now,
            currentUserID: userID))

        var permissive = valid
        permissive.permissions = 0o644
        XCTAssertFalse(HostIntegrationGate.allows(
            environment: environment,
            marker: permissive,
            now: now,
            currentUserID: userID))

        var notRegular = valid
        notRegular.isRegularFile = false
        XCTAssertFalse(HostIntegrationGate.allows(
            environment: environment,
            marker: notRegular,
            now: now,
            currentUserID: userID))
    }

    func testMissingOrShortEnvironmentValuesDefaultToDenied() {
        XCTAssertFalse(HostIntegrationGate.allows(
            environment: [:],
            marker: validMarker(),
            now: now,
            currentUserID: userID))
        XCTAssertFalse(HostIntegrationGate.allows(
            environment: [
                HostIntegrationGate.tokenEnvironmentKey: "short",
                HostIntegrationGate.markerEnvironmentKey: path,
            ],
            marker: validMarker(),
            now: now,
            currentUserID: userID))
    }

    func testReadsOwnedTokenFileAndRejectsMismatchedToken() throws {
        let markerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("talkie-host-gate-\(UUID().uuidString)")
        try Data("\(token)\n".utf8).write(to: markerURL, options: .withoutOverwriting)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: markerURL.path)
        defer { try? FileManager.default.removeItem(at: markerURL) }

        var environment = validEnvironment()
        environment[HostIntegrationGate.markerEnvironmentKey] = markerURL.path
        XCTAssertTrue(HostIntegrationGate.isEnabled(environment: environment))

        environment[HostIntegrationGate.tokenEnvironmentKey] = String(repeating: "z", count: token.count)
        XCTAssertFalse(HostIntegrationGate.isEnabled(environment: environment))
    }

    private func validEnvironment() -> [String: String] {
        [
            HostIntegrationGate.tokenEnvironmentKey: token,
            HostIntegrationGate.markerEnvironmentKey: path,
        ]
    }

    private func validMarker() -> HostIntegrationGate.Marker {
        HostIntegrationGate.Marker(
            token: token,
            ownerUserID: userID,
            modifiedAt: now,
            isRegularFile: true,
            permissions: 0o600)
    }
}
