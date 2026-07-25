import XCTest
@testable import Talkie

@MainActor
final class AppEnvironmentTests: XCTestCase {
    func testNormalLaunchUsesProductionEnvironment() {
        let environment = AppEnvironment.launch(arguments: ["Talkie"])

        XCTAssertEqual(environment.mode, .production)
        XCTAssertFalse(environment.historyInMemory)
        XCTAssertNil(environment.e2e)
    }

    func testE2ELaunchUsesIsolatedStateAndFakeCredentials() throws {
        let paths = try E2EBridgePaths.createSharedSession(sessionID: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: paths.sessionDirectoryURL) }
        let environment = AppEnvironment.launch(arguments: [
            "Talkie", "--e2e", "--e2e-session", paths.sessionID,
            "--e2e-scenario", "happy-path",
            "--e2e-shared-root", paths.sharedRootURL.path,
        ])

        XCTAssertEqual(environment.mode, .e2e)
        XCTAssertTrue(environment.historyInMemory)
        XCTAssertEqual(environment.e2e?.sessionID, paths.sessionID)
        XCTAssertEqual(environment.e2e?.scenario, "happy-path")
        XCTAssertEqual(environment.e2e?.reportURL, paths.reportURL)
        XCTAssertEqual(environment.e2e?.commandURL, paths.commandURL)
        XCTAssertEqual(environment.credentialOverrides[.openAIKey], "e2e-openai-key")
        XCTAssertEqual(environment.credentialOverrides[.openRouterKey], "e2e-openrouter-key")
    }

    func testE2ELaunchGeneratesSessionAndReportWhenOmitted() throws {
        let environment = AppEnvironment.launch(arguments: ["Talkie", "--e2e"])

        let configuration = try XCTUnwrap(environment.e2e)
        XCTAssertFalse(configuration.sessionID.isEmpty)
        XCTAssertEqual(configuration.reportURL.lastPathComponent, "report.jsonl")
        XCTAssertEqual(configuration.commandURL.lastPathComponent, "commands")
        defer {
            try? FileManager.default.removeItem(
                at: configuration.reportURL.deletingLastPathComponent())
        }
    }

    func testE2EBridgePathsCreatePrivateSharedSessionAndResolveSameFiles() throws {
        let sessionID = UUID().uuidString
        let paths = try E2EBridgePaths.createSharedSession(sessionID: sessionID)
        defer { try? FileManager.default.removeItem(at: paths.sessionDirectoryURL) }

        let resolved = try E2EBridgePaths.resolveExistingSharedSession(
            sessionID: sessionID,
            sharedRootPath: paths.sharedRootURL.path)

        XCTAssertEqual(resolved, paths)
        XCTAssertEqual(paths.reportURL.lastPathComponent, "report.jsonl")
        XCTAssertEqual(paths.commandURL.lastPathComponent, "commands")
        let attributes = try FileManager.default.attributesOfItem(
            atPath: paths.sessionDirectoryURL.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }

    func testE2EBridgePathsRejectTraversalAndExistingSymlink() throws {
        XCTAssertThrowsError(try E2EBridgePaths.createSharedSession(sessionID: "../escape"))

        let sessionID = UUID().uuidString
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
        let sessionDirectory = root.appendingPathComponent("talkie-ui-\(sessionID)")
        try FileManager.default.createSymbolicLink(
            at: sessionDirectory,
            withDestinationURL: root)
        defer { try? FileManager.default.removeItem(at: sessionDirectory) }

        XCTAssertThrowsError(try E2EBridgePaths.resolveExistingSharedSession(
            sessionID: sessionID,
            sharedRootPath: root.path))
    }

    func testScreenshotDemoUsesIsolatedCredentialFreeState() {
        let environment = AppEnvironment.launch(arguments: [
            "Talkie", "--screenshot-demo",
            "--screenshot-demo-session", "docs-session",
        ])

        XCTAssertEqual(environment.mode, .screenshotDemo)
        XCTAssertTrue(environment.historyInMemory)
        XCTAssertTrue(environment.credentialOverrides.isEmpty)
        XCTAssertNil(environment.e2e)
        XCTAssertEqual(environment.keychainService,
                       "com.archiev.talkie.screenshot.docs-session")
        XCTAssertEqual(environment.defaults.string(forKey: "engineMode"), "local")
        XCTAssertEqual(environment.defaults.string(forKey: "cleanupLevel"), "none")
        XCTAssertEqual(environment.defaults.string(forKey: "cleanupProvider"), "openai")
        XCTAssertEqual(environment.defaults.string(forKey: "selectedProfileID"),
                       DictationProfile.privateOffline.id.uuidString)
        XCTAssertEqual(environment.defaults.string(forKey: "pillStyle"),
                       PillStyle.calmFlowRibbon.rawValue)
        XCTAssertEqual(environment.defaults.string(forKey: "pinnedLanguage"), "en")
    }
}
