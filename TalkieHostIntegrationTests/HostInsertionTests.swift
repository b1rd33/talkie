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
        let sessionDirectory = URL(fileURLWithPath: "/private/tmp/talkie-ui-\(session)")
        let report = sessionDirectory.appendingPathComponent("report.jsonl")

        let host = XCUIApplication(bundleIdentifier: bundleID)
        guard host.state == .notRunning else {
            throw XCTSkip("Close \(name) before running isolated host fixtures; existing windows are preserved.")
        }
        host.launch(); XCTAssertTrue(host.wait(for: .runningForeground, timeout: 5), name)
        host.typeKey("n", modifierFlags: .command)

        let talkie = XCUIApplication()
        talkie.launchArguments = ["--e2e", "--e2e-session", session,
            "--e2e-scenario", "host-\(name)",
            "--e2e-fixture-text", fixture]
        talkie.launch()
        defer {
            host.activate()
            host.typeKey("a", modifierFlags: .command)
            host.typeKey(XCUIKeyboardKey.delete.rawValue, modifierFlags: [])
            talkie.terminate()
            host.terminate()
            try? FileManager.default.removeItem(at: sessionDirectory)
        }
        host.activate()
        try append("press", report: report); try append("release", report: report)

        let predicate = NSPredicate { _, _ in
            (try? String(contentsOf: report, encoding: .utf8))?.contains("\"passed\":true") == true
        }
        expectation(for: predicate, evaluatedWith: NSObject()); waitForExpectations(timeout: 8)
        host.activate(); host.typeKey("a", modifierFlags: .command); host.typeKey("c", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertTrue(NSPasteboard.general.string(forType: .string)?.contains(fixture) == true,
                      "\(name) did not receive the fixture through Talkie's real insertion stack")
    }

    private func append(_ command: String, report: URL) throws {
        let url = report.deletingLastPathComponent().appendingPathComponent("commands")
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: url.path) { Thread.sleep(forTimeInterval: 0.02) }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("\(command)\n".utf8))
    }
}
