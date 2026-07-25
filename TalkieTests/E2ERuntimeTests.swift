#if DEBUG
import XCTest
@testable import Talkie

@MainActor
final class E2ERuntimeTests: XCTestCase {
    func testReporterPublishesTypedSessionScopedPrivacySafeNotification() throws {
        let paths = try E2EBridgePaths.createSharedSession(sessionID: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: paths.sessionDirectoryURL) }
        let configuration = E2ELaunchConfiguration(
            sessionID: paths.sessionID,
            scenario: "notification-report",
            reportURL: paths.reportURL,
            commandURL: paths.commandURL,
            fixtureText: nil)
        let published = expectation(description: "typed report notification")
        var payload: Data?
        let center = DistributedNotificationCenter.default()
        let observer = center.addObserver(
            forName: E2EBridgeNotifications.reportName(sessionID: paths.sessionID),
            object: nil,
            queue: .main
        ) { notification in
            payload = notification.userInfo?[E2EBridgeNotifications.reportPayloadKey] as? Data
            published.fulfill()
        }
        defer { center.removeObserver(observer) }
        let reporter = try E2EReporter(configuration: configuration)

        reporter.record(
            state: "idle",
            targetBundleID: "com.apple.TextEdit",
            deliveryRoute: "insert",
            passed: true)

        wait(for: [published], timeout: 1)
        let data = try XCTUnwrap(payload)
        let entry = try JSONDecoder().decode(E2EReportEntry.self, from: data)
        XCTAssertEqual(entry.state, "idle")
        XCTAssertEqual(entry.passed, true)
        XCTAssertEqual(entry.scenario, "notification-report")
        let raw = String(decoding: data, as: UTF8.self)
        for forbidden in ["transcript", "clipboard", "apiKey", "selectedText", "context"] {
            XCTAssertFalse(raw.localizedCaseInsensitiveContains(forbidden))
        }
    }

    func testBridgeAnnouncesReadyAfterInstallingSessionScopedCommandObserver() throws {
        let paths = try E2EBridgePaths.createSharedSession(sessionID: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: paths.sessionDirectoryURL) }
        let configuration = E2ELaunchConfiguration(
            sessionID: paths.sessionID,
            scenario: "ready-command",
            reportURL: paths.reportURL,
            commandURL: paths.commandURL,
            fixtureText: nil)
        let center = DistributedNotificationCenter.default()
        let ready = expectation(description: "bridge ready")
        let recorded = expectation(description: "command produced report")
        let reportObserver = center.addObserver(
            forName: E2EBridgeNotifications.reportName(sessionID: paths.sessionID),
            object: nil,
            queue: .main
        ) { notification in
            guard let payload = notification.userInfo?[
                E2EBridgeNotifications.reportPayloadKey] as? Data,
                  let entry = try? JSONDecoder().decode(
                    E2EReportEntry.self,
                    from: payload),
                  entry.state == "recording" else { return }
            recorded.fulfill()
        }
        let readyObserver = center.addObserver(
            forName: E2EBridgeNotifications.readyName(sessionID: paths.sessionID),
            object: nil,
            queue: .main
        ) { _ in
            ready.fulfill()
        }
        defer {
            center.removeObserver(readyObserver)
            center.removeObserver(reportObserver)
        }
        let reporter = try E2EReporter(configuration: configuration)
        let runtime = E2ERuntime(reporter: reporter, targetBundleID: { nil })
        let bridge = E2ETestControlBridge(configuration: configuration, runtime: runtime)

        try bridge.start()

        wait(for: [ready], timeout: 1)
        center.postNotificationName(
            E2EBridgeNotifications.commandName(
                sessionID: paths.sessionID,
                command: .press),
            object: nil,
            userInfo: nil,
            deliverImmediately: true)
        wait(for: [recorded], timeout: 1)
    }

    func testBridgeRespondsToReadyRequestAfterInitialAnnouncementWasMissed() throws {
        let paths = try E2EBridgePaths.createSharedSession(sessionID: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: paths.sessionDirectoryURL) }
        let configuration = E2ELaunchConfiguration(
            sessionID: paths.sessionID,
            scenario: "ready-retry",
            reportURL: paths.reportURL,
            commandURL: paths.commandURL,
            fixtureText: nil)
        let reporter = try E2EReporter(configuration: configuration)
        let runtime = E2ERuntime(reporter: reporter, targetBundleID: { nil })
        let bridge = E2ETestControlBridge(configuration: configuration, runtime: runtime)
        try bridge.start()

        let center = DistributedNotificationCenter.default()
        let ready = expectation(description: "bridge re-announced readiness")
        let observer = center.addObserver(
            forName: E2EBridgeNotifications.readyName(sessionID: paths.sessionID),
            object: nil,
            queue: .main
        ) { _ in
            ready.fulfill()
        }
        defer { center.removeObserver(observer) }

        center.postNotificationName(
            E2EBridgeNotifications.readyRequestName(sessionID: paths.sessionID),
            object: nil,
            userInfo: nil,
            deliverImmediately: true)

        wait(for: [ready], timeout: 1)
    }

    func testBridgeStopRemovesOnlyAppOwnedSessionDirectory() throws {
        let paths = try E2EBridgePaths.createSharedSession(sessionID: UUID().uuidString)
        let configuration = E2ELaunchConfiguration(
            sessionID: paths.sessionID,
            scenario: "owned-session",
            reportURL: paths.reportURL,
            commandURL: paths.commandURL,
            fixtureText: nil,
            ownsSessionDirectory: true)
        let reporter = try E2EReporter(configuration: configuration)
        let runtime = E2ERuntime(reporter: reporter, targetBundleID: { nil })
        let bridge = E2ETestControlBridge(configuration: configuration, runtime: runtime)
        try bridge.start()

        bridge.stop()

        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.sessionDirectoryURL.path))
    }

    func testBridgeStopPreservesExternallyOwnedSessionDirectory() throws {
        let paths = try E2EBridgePaths.createSharedSession(sessionID: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: paths.sessionDirectoryURL) }
        let configuration = E2ELaunchConfiguration(
            sessionID: paths.sessionID,
            scenario: "external-session",
            reportURL: paths.reportURL,
            commandURL: paths.commandURL,
            fixtureText: nil)
        let reporter = try E2EReporter(configuration: configuration)
        let runtime = E2ERuntime(reporter: reporter, targetBundleID: { nil })
        let bridge = E2ETestControlBridge(configuration: configuration, runtime: runtime)
        try bridge.start()

        bridge.stop()

        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.sessionDirectoryURL.path))
    }

    func testPressReleaseProducesPrivacySafePassingReport() throws {
        let paths = try E2EBridgePaths.createSharedSession(sessionID: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: paths.sessionDirectoryURL) }
        let url = paths.reportURL
        let reporter = try E2EReporter(configuration: E2ELaunchConfiguration(
            sessionID: "session-1", scenario: "happy-path", reportURL: url,
            fixtureText: nil))
        try assertPrivateRegularFile(url)
        let runtime = E2ERuntime(reporter: reporter,
                                 targetBundleID: { "com.apple.TextEdit" })

        runtime.handle(.press)
        runtime.handle(.release)

        let entries = try reporter.readEntries()
        XCTAssertEqual(entries.map(\.state), ["recording", "transcribing", "inserting", "idle"])
        XCTAssertEqual(entries.last?.deliveryRoute, "insert")
        XCTAssertEqual(entries.last?.passed, true)
        let raw = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(raw.contains("transcript"))
        XCTAssertFalse(raw.contains("clipboard"))
        XCTAssertFalse(raw.contains("api_key"))
        try assertPrivateRegularFile(url)
    }

    func testCancelAndHandsFreeCommandsAreDeterministic() throws {
        let paths = try E2EBridgePaths.createSharedSession(sessionID: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: paths.sessionDirectoryURL) }
        let url = paths.reportURL
        let reporter = try E2EReporter(configuration: E2ELaunchConfiguration(
            sessionID: "session-2", scenario: "cancel", reportURL: url,
            fixtureText: nil))
        let runtime = E2ERuntime(reporter: reporter, targetBundleID: { nil })

        runtime.handle(.toggleHandsFree)
        runtime.handle(.cancel)

        XCTAssertEqual(try reporter.readEntries().map(\.state), ["recording", "idle"])
    }

    func testReporterRejectsAnExistingReportFile() throws {
        let paths = try E2EBridgePaths.createSharedSession(sessionID: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: paths.sessionDirectoryURL) }
        try Data().write(to: paths.reportURL, options: .withoutOverwriting)
        let configuration = E2ELaunchConfiguration(
            sessionID: paths.sessionID,
            scenario: "existing-report",
            reportURL: paths.reportURL,
            commandURL: paths.commandURL,
            fixtureText: nil)

        XCTAssertThrowsError(try E2EReporter(configuration: configuration))
    }

    func testCommandBridgeRejectsAnExistingCommandDirectory() throws {
        let paths = try E2EBridgePaths.createSharedSession(sessionID: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: paths.sessionDirectoryURL) }
        try FileManager.default.createDirectory(
            at: paths.commandURL,
            withIntermediateDirectories: false)
        let configuration = E2ELaunchConfiguration(
            sessionID: paths.sessionID,
            scenario: "existing-command-directory",
            reportURL: paths.reportURL,
            commandURL: paths.commandURL,
            fixtureText: nil)
        let reporter = try E2EReporter(configuration: configuration)
        let runtime = E2ERuntime(reporter: reporter, targetBundleID: { nil })
        let bridge = E2ETestControlBridge(configuration: configuration, runtime: runtime)

        XCTAssertThrowsError(try bridge.start())
    }

    func testCommandBridgeCreatesPrivateRegularFileAndPreservesPermissionsAfterWrite() throws {
        let paths = try E2EBridgePaths.createSharedSession(sessionID: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: paths.sessionDirectoryURL) }
        let configuration = E2ELaunchConfiguration(
            sessionID: paths.sessionID,
            scenario: "private-command-file",
            reportURL: paths.reportURL,
            commandURL: paths.commandURL,
            fixtureText: nil)
        let reporter = try E2EReporter(configuration: configuration)

        do {
            let runtime = E2ERuntime(reporter: reporter, targetBundleID: { nil })
            let bridge = E2ETestControlBridge(configuration: configuration, runtime: runtime)
            try bridge.start()
            try assertPrivateRegularFile(paths.commandURL)

            let handle = try FileHandle(forWritingTo: paths.commandURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data("press\n".utf8))
            try assertPrivateRegularFile(paths.commandURL)
        }
    }

    private func assertPrivateRegularFile(
        _ url: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let fileManager = FileManager.default
        XCTAssertNil(
            try? fileManager.destinationOfSymbolicLink(atPath: url.path),
            "must not be a symbolic link",
            file: file,
            line: line)
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        XCTAssertEqual(
            attributes[.type] as? FileAttributeType,
            .typeRegular,
            file: file,
            line: line)
        XCTAssertEqual(
            (attributes[.posixPermissions] as? NSNumber)?.intValue,
            0o600,
            file: file,
            line: line)
    }
}
#endif
