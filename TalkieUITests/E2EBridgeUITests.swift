import XCTest

final class E2EBridgeUITests: XCTestCase {
    func testPressReleaseProducesPrivacySafePassingReport() throws {
        let session = UUID().uuidString
        let report = FileManager.default.temporaryDirectory
            .appendingPathComponent("talkie-ui-\(session).jsonl")
        defer { try? FileManager.default.removeItem(at: report) }

        let app = XCUIApplication()
        app.launchArguments = ["--e2e", "--e2e-session", session,
                               "--e2e-scenario", "press-release",
                               "--e2e-report", report.path]
        app.launch()

        post("press", report: report)
        post("release", report: report)

        let predicate = NSPredicate { _, _ in
            guard let data = try? Data(contentsOf: report),
                  let text = String(data: data, encoding: .utf8) else { return false }
            return text.contains("\"passed\":true") && text.contains("\"state\":\"idle\"")
        }
        expectation(for: predicate, evaluatedWith: NSObject())
        waitForExpectations(timeout: 5)

        let reportText = try String(contentsOf: report, encoding: .utf8)
        for forbidden in ["transcript", "clipboard", "apiKey", "selectedText", "context"] {
            XCTAssertFalse(reportText.localizedCaseInsensitiveContains(forbidden))
        }
    }

    func testHandsFreeAndCancelCommandsStayDeterministic() throws {
        let session = UUID().uuidString
        let report = FileManager.default.temporaryDirectory
            .appendingPathComponent("talkie-ui-\(session).jsonl")
        defer { try? FileManager.default.removeItem(at: report) }
        let app = XCUIApplication()
        app.launchArguments = ["--e2e", "--e2e-session", session,
                               "--e2e-scenario", "hands-free-cancel",
                               "--e2e-report", report.path]
        app.launch()
        post("toggleHandsFree", report: report)
        post("cancel", report: report)
        let predicate = NSPredicate { _, _ in
            (try? String(contentsOf: report, encoding: .utf8))?.contains("\"reason\":\"cancelled\"") == true
        }
        expectation(for: predicate, evaluatedWith: NSObject())
        waitForExpectations(timeout: 5)
    }

    private func post(_ command: String, report: URL) {
        let url = report.appendingPathExtension("commands")
        for _ in 0..<50 where !FileManager.default.fileExists(atPath: url.path) {
            Thread.sleep(forTimeInterval: 0.02)
        }
        let handle = try! FileHandle(forWritingTo: url)
        try! handle.seekToEnd()
        handle.write(Data("\(command)\n".utf8))
        try? handle.close()
    }
}
