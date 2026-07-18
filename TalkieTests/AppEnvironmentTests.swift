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
        let environment = AppEnvironment.launch(arguments: [
            "Talkie", "--e2e", "--e2e-session", "session-123",
            "--e2e-scenario", "happy-path",
            "--e2e-report", "/tmp/talkie-e2e-session-123.jsonl",
        ])

        XCTAssertEqual(environment.mode, .e2e)
        XCTAssertTrue(environment.historyInMemory)
        XCTAssertEqual(environment.e2e?.sessionID, "session-123")
        XCTAssertEqual(environment.e2e?.scenario, "happy-path")
        XCTAssertEqual(environment.e2e?.reportURL.path, "/tmp/talkie-e2e-session-123.jsonl")
        XCTAssertEqual(environment.credentialOverrides[.openAIKey], "e2e-openai-key")
        XCTAssertEqual(environment.credentialOverrides[.openRouterKey], "e2e-openrouter-key")
    }

    func testE2ELaunchGeneratesSessionAndReportWhenOmitted() throws {
        let environment = AppEnvironment.launch(arguments: ["Talkie", "--e2e"])

        let configuration = try XCTUnwrap(environment.e2e)
        XCTAssertFalse(configuration.sessionID.isEmpty)
        XCTAssertTrue(configuration.reportURL.lastPathComponent.contains(configuration.sessionID))
    }
}
