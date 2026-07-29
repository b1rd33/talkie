import XCTest
@testable import Talkie

@MainActor
final class AppEnvironmentTests: XCTestCase {
    func testNormalLaunchUsesProductionEnvironment() {
        let environment = AppEnvironment.launch(arguments: ["Talkie"])

        XCTAssertEqual(environment.mode, .production)
        XCTAssertFalse(environment.historyInMemory)
        XCTAssertNil(environment.e2e)
        XCTAssertEqual(AppDelegate.launchAction(for: environment.mode), .startProductionUI)
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
        XCTAssertEqual(environment.e2e?.ownsSessionDirectory, false)
        XCTAssertEqual(environment.credentialOverrides[.openAIKey], "e2e-openai-key")
        XCTAssertEqual(environment.credentialOverrides[.openRouterKey], "e2e-openrouter-key")
        XCTAssertEqual(
            environment.defaults.string(forKey: "transcriptionModel"),
            "gpt-transcribe")
        XCTAssertEqual(
            environment.defaults.string(forKey: "realtimeTranscriptionModel"),
            "gpt-live-transcribe")
        XCTAssertEqual(
            environment.defaults.string(forKey: "realtimeTranscriptionDelay"),
            "medium")
        XCTAssertEqual(
            environment.defaults.stringArray(forKey: "expectedInputLanguages"),
            ["en"])
        XCTAssertEqual(
            environment.defaults.object(forKey: "streamBatchTranscription") as? Bool,
            false)
        XCTAssertEqual(AppDelegate.launchAction(for: environment.mode), .startE2E)
    }

    func testE2ELaunchGeneratesSessionAndReportWhenOmitted() throws {
        let environment = AppEnvironment.launch(arguments: ["Talkie", "--e2e"])

        let configuration = try XCTUnwrap(environment.e2e)
        XCTAssertFalse(configuration.sessionID.isEmpty)
        XCTAssertEqual(configuration.reportURL.lastPathComponent, "report.jsonl")
        XCTAssertEqual(configuration.commandURL.lastPathComponent, "commands")
        XCTAssertTrue(configuration.ownsSessionDirectory)
        defer {
            try? FileManager.default.removeItem(
                at: configuration.reportURL.deletingLastPathComponent())
        }
    }

    func testE2ELaunchRejectsUnsafeSharedRootWithoutProductionFallback() {
        assertRejectedE2ELaunch([
            "--e2e-session", UUID().uuidString,
            "--e2e-shared-root", "/private/var/tmp",
        ])
    }

    func testE2ELaunchRejectsInvalidSessionIDWithoutProductionFallback() {
        assertRejectedE2ELaunch([
            "--e2e-session", "../production",
            "--e2e-shared-root", "/private/tmp",
        ])
    }

    func testE2ELaunchRejectsMissingSharedSessionWithoutProductionFallback() {
        assertRejectedE2ELaunch([
            "--e2e-session", UUID().uuidString,
            "--e2e-shared-root", "/private/tmp",
        ])
    }

    func testE2ELaunchRejectsNonPrivateSessionWithoutProductionFallback() throws {
        let sessionID = UUID().uuidString
        let sessionDirectory = E2EBridgePaths.neutralSharedRootURL
            .appendingPathComponent("talkie-ui-\(sessionID)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sessionDirectory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o755])
        defer { try? FileManager.default.removeItem(at: sessionDirectory) }

        assertRejectedE2ELaunch([
            "--e2e-session", sessionID,
            "--e2e-shared-root", "/private/tmp",
        ])
    }

    func testE2ELaunchRejectsSymlinkSessionWithoutProductionFallback() throws {
        let sessionID = UUID().uuidString
        let sessionDirectory = E2EBridgePaths.neutralSharedRootURL
            .appendingPathComponent("talkie-ui-\(sessionID)", isDirectory: true)
        try FileManager.default.createSymbolicLink(
            at: sessionDirectory,
            withDestinationURL: E2EBridgePaths.neutralSharedRootURL)
        defer { try? FileManager.default.removeItem(at: sessionDirectory) }

        assertRejectedE2ELaunch([
            "--e2e-session", sessionID,
            "--e2e-shared-root", "/private/tmp",
        ])
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
        XCTAssertEqual(AppDelegate.launchAction(for: environment.mode), .startScreenshotDemo)
    }

    private func assertRejectedE2ELaunch(
        _ e2eArguments: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let environment = AppEnvironment.launch(
            arguments: ["Talkie", "--e2e"] + e2eArguments)

        XCTAssertEqual(environment.mode, .invalidE2E, file: file, line: line)
        XCTAssertFalse(environment.defaults === UserDefaults.standard, file: file, line: line)
        XCTAssertNotEqual(
            environment.keychainService,
            "com.archiev.talkie",
            file: file,
            line: line)
        XCTAssertTrue(environment.historyInMemory, file: file, line: line)
        XCTAssertTrue(environment.credentialOverrides.isEmpty, file: file, line: line)
        XCTAssertNil(environment.e2e, file: file, line: line)
        XCTAssertEqual(
            AppDelegate.launchAction(for: environment.mode),
            .terminate,
            file: file,
            line: line)
    }
}
