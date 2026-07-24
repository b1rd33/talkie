import AppKit
import XCTest

final class HostInsertionTests: XCTestCase {
    func testTextEditInsertion() throws { try verifyHost(bundleID: "com.apple.TextEdit", name: "TextEdit") }
    func testNotesInsertion() throws { try verifyHost(bundleID: "com.apple.Notes", name: "Notes") }
    func testTerminalInsertion() throws { try verifyHost(bundleID: "com.apple.Terminal", name: "Terminal") }

    private func verifyHost(bundleID: String, name: String) throws {
        guard HostIntegrationGate.isEnabled() else {
            throw XCTSkip("Run scripts/host-integration.sh on a signed, Accessibility-approved test Mac.")
        }
        let fixture = "Talkie host test \(UUID().uuidString)"
        let session = UUID().uuidString
        let report = FileManager.default.temporaryDirectory.appendingPathComponent("talkie-host-\(session).jsonl")

        let host = XCUIApplication(bundleIdentifier: bundleID)
        host.launch(); XCTAssertTrue(host.wait(for: .runningForeground, timeout: 5), name)
        host.typeKey("n", modifierFlags: .command)

        let talkie = XCUIApplication()
        talkie.launchArguments = ["--e2e", "--e2e-session", session,
            "--e2e-scenario", "host-\(name)", "--e2e-report", report.path,
            "--e2e-fixture-text", fixture]
        talkie.launch()
        defer {
            host.activate()
            host.typeKey("a", modifierFlags: .command)
            host.typeKey(XCUIKeyboardKey.delete.rawValue, modifierFlags: [])
            talkie.terminate()
            host.terminate()
            try? FileManager.default.removeItem(at: report)
            try? FileManager.default.removeItem(at: report.appendingPathExtension("commands"))
        }
        host.activate()
        append("press", report: report); append("release", report: report)

        let predicate = NSPredicate { _, _ in
            (try? String(contentsOf: report, encoding: .utf8))?.contains("\"passed\":true") == true
        }
        expectation(for: predicate, evaluatedWith: NSObject()); waitForExpectations(timeout: 8)
        host.activate(); host.typeKey("a", modifierFlags: .command); host.typeKey("c", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertTrue(NSPasteboard.general.string(forType: .string)?.contains(fixture) == true,
                      "\(name) did not receive the fixture through Talkie's real insertion stack")
    }

    private func append(_ command: String, report: URL) {
        let url = report.appendingPathExtension("commands")
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: url.path) { Thread.sleep(forTimeInterval: 0.02) }
        let handle = try! FileHandle(forWritingTo: url); try! handle.seekToEnd()
        handle.write(Data("\(command)\n".utf8)); try? handle.close()
    }
}
