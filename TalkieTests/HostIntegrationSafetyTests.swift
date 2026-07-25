import Foundation
import XCTest

final class HostIntegrationSafetyTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var scriptURL: URL {
        root.appendingPathComponent("scripts/host-integration.sh")
    }

    func testHostScriptUsesPerRunTokenAndMarkerInsteadOfFixedSentinel() throws {
        let script = try String(
            contentsOf: scriptURL,
            encoding: .utf8)

        XCTAssertTrue(script.contains("mktemp"))
        XCTAssertTrue(script.contains("TALKIE_HOST_INTEGRATION_TOKEN"))
        XCTAssertTrue(script.contains("TALKIE_HOST_INTEGRATION_MARKER"))
        let legacyMarker = "/tmp/talkie-host-integration." + "enabled"
        let legacyFlag = "TALKIE_RUN_" + "HOST_INTEGRATION"
        XCTAssertFalse(script.contains(legacyMarker))
        XCTAssertFalse(script.contains(legacyFlag))
    }

    func testHostScriptBuildsBeforeAuthorizationAndTestsWithoutBuilding() throws {
        let lines = try String(contentsOf: scriptURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)

        let build = try XCTUnwrap(lines.firstIndex { $0.contains("xcodebuild build-for-testing") })
        let marker = try XCTUnwrap(lines.firstIndex { $0.contains("host_integration_marker=") })
        let test = try XCTUnwrap(lines.firstIndex { $0.contains("xcodebuild test-without-building") })
        let result = try XCTUnwrap(lines.firstIndex {
            $0.contains(#"validate_host_result "$host_integration_summary""#)
        })

        XCTAssertLessThan(build, marker)
        XCTAssertLessThan(marker, test)
        XCTAssertLessThan(test, result)
        XCTAssertTrue(lines.contains { $0.contains("-resultBundlePath") })
    }

    func testStructuredResultValidationRejectsSkippedFailedAndWrongCounts() throws {
        XCTAssertEqual(try validate(summary: [
            "totalTestCount": 3,
            "passedTests": 3,
            "failedTests": 0,
            "skippedTests": 0,
            "result": "Passed",
        ]), 0)

        XCTAssertNotEqual(try validate(summary: [
            "totalTestCount": 3,
            "passedTests": 0,
            "failedTests": 0,
            "skippedTests": 3,
            "result": "Passed",
        ]), 0)

        XCTAssertNotEqual(try validate(summary: [
            "totalTestCount": 3,
            "passedTests": 2,
            "failedTests": 1,
            "skippedTests": 0,
            "result": "Failed",
        ]), 0)

        XCTAssertNotEqual(try validate(summary: [
            "totalTestCount": 2,
            "passedTests": 2,
            "failedTests": 0,
            "skippedTests": 0,
            "result": "Passed",
        ]), 0)
    }

    func testOrdinarySchemeExcludesHostIntegrationTarget() throws {
        let schemes = root.appendingPathComponent("Talkie.xcodeproj/xcshareddata/xcschemes")
        let ordinary = try String(
            contentsOf: schemes.appendingPathComponent("Talkie.xcscheme"),
            encoding: .utf8)
        let dedicated = try String(
            contentsOf: schemes.appendingPathComponent("TalkieHostIntegration.xcscheme"),
            encoding: .utf8)

        XCTAssertFalse(ordinary.contains("TalkieHostIntegrationTests"))
        XCTAssertTrue(dedicated.contains("TalkieHostIntegrationTests"))
    }

    private func validate(summary: [String: Any]) throws -> Int32 {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("talkie-host-script-test-\(UUID().uuidString)")
        let fakeBin = directory.appendingPathComponent("bin")
        try FileManager.default.createDirectory(
            at: fakeBin,
            withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let summaryURL = directory.appendingPathComponent("summary.json")
        try JSONSerialization.data(withJSONObject: summary)
            .write(to: summaryURL)
        let fakeXcodegen = fakeBin.appendingPathComponent("xcodegen")
        try Data("#!/bin/sh\nexit 99\n".utf8).write(to: fakeXcodegen)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: fakeXcodegen.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path, "--validate-summary", summaryURL.path]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(fakeBin.path):\(environment["PATH"] ?? "/usr/bin:/bin")"
        environment["TMPDIR"] = directory.path
        process.environment = environment
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
