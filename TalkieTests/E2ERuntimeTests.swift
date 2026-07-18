#if DEBUG
import XCTest
@testable import Talkie

@MainActor
final class E2ERuntimeTests: XCTestCase {
    func testPressReleaseProducesPrivacySafePassingReport() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("talkie-e2e-report-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let reporter = try E2EReporter(configuration: E2ELaunchConfiguration(
            sessionID: "session-1", scenario: "happy-path", reportURL: url,
            fixtureText: nil))
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
    }

    func testCancelAndHandsFreeCommandsAreDeterministic() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("talkie-e2e-report-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let reporter = try E2EReporter(configuration: E2ELaunchConfiguration(
            sessionID: "session-2", scenario: "cancel", reportURL: url,
            fixtureText: nil))
        let runtime = E2ERuntime(reporter: reporter, targetBundleID: { nil })

        runtime.handle(.toggleHandsFree)
        runtime.handle(.cancel)

        XCTAssertEqual(try reporter.readEntries().map(\.state), ["recording", "idle"])
    }
}
#endif
