import XCTest

final class E2EBridgeUITests: XCTestCase {
    func testPressReleaseProducesPrivacySafePassingReport() throws {
        let paths = try UITestBridgePaths()
        let app = XCUIApplication()
        defer {
            app.terminate()
            paths.remove()
        }
        app.launchArguments = ["--e2e", "--e2e-session", paths.sessionID,
                               "--e2e-scenario", "press-release",
                               "--e2e-shared-root", paths.sharedRootURL.path]
        app.launch()

        try post("press", commandURL: paths.commandURL)
        try post("release", commandURL: paths.commandURL)

        let predicate = NSPredicate { _, _ in
            guard let data = try? Data(contentsOf: paths.reportURL),
                  let text = String(data: data, encoding: .utf8) else { return false }
            return text.contains("\"passed\":true") && text.contains("\"state\":\"idle\"")
        }
        expectation(for: predicate, evaluatedWith: NSObject())
        waitForExpectations(timeout: 5)

        let reportText = try String(contentsOf: paths.reportURL, encoding: .utf8)
        for forbidden in ["transcript", "clipboard", "apiKey", "selectedText", "context"] {
            XCTAssertFalse(reportText.localizedCaseInsensitiveContains(forbidden))
        }
    }

    func testHandsFreeAndCancelCommandsStayDeterministic() throws {
        let paths = try UITestBridgePaths()
        let app = XCUIApplication()
        defer {
            app.terminate()
            paths.remove()
        }
        app.launchArguments = ["--e2e", "--e2e-session", paths.sessionID,
                               "--e2e-scenario", "hands-free-cancel",
                               "--e2e-shared-root", paths.sharedRootURL.path]
        app.launch()
        try post("toggleHandsFree", commandURL: paths.commandURL)
        try post("cancel", commandURL: paths.commandURL)
        let predicate = NSPredicate { _, _ in
            (try? String(contentsOf: paths.reportURL, encoding: .utf8))?
                .contains("\"reason\":\"cancelled\"") == true
        }
        expectation(for: predicate, evaluatedWith: NSObject())
        waitForExpectations(timeout: 5)
    }

    private func post(_ command: String, commandURL: URL) throws {
        for _ in 0..<50 where !FileManager.default.fileExists(atPath: commandURL.path) {
            Thread.sleep(forTimeInterval: 0.02)
        }
        let handle = try FileHandle(forWritingTo: commandURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("\(command)\n".utf8))
    }
}

private struct UITestBridgePaths {
    static let sharedRootURL = URL(fileURLWithPath: "/private/tmp", isDirectory: true)

    let sessionID: String
    let sharedRootURL: URL
    let sessionDirectoryURL: URL
    let reportURL: URL
    let commandURL: URL

    init(fileManager: FileManager = .default) throws {
        let sessionID = UUID().uuidString
        let sessionDirectory = Self.sharedRootURL.appendingPathComponent(
            "talkie-ui-\(sessionID)",
            isDirectory: true)
        guard !fileManager.fileExists(atPath: sessionDirectory.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        try fileManager.createDirectory(
            at: sessionDirectory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        let attributes = try fileManager.attributesOfItem(atPath: sessionDirectory.path)
        guard (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700 else {
            throw CocoaError(.fileWriteNoPermission)
        }
        self.sessionID = sessionID
        self.sharedRootURL = Self.sharedRootURL
        self.sessionDirectoryURL = sessionDirectory
        reportURL = sessionDirectory.appendingPathComponent("report.jsonl")
        commandURL = sessionDirectory.appendingPathComponent("commands")
    }

    func remove(fileManager: FileManager = .default) {
        try? fileManager.removeItem(at: sessionDirectoryURL)
    }
}
