import XCTest

@MainActor
final class SettingsUITests: XCTestCase {
    func testAdvancedEnginesExposeTranscriptionControls() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--e2e",
            "--e2e-session", UUID().uuidString,
            "--e2e-scenario", "settings-model-controls",
        ]
        app.launch()
        defer { app.terminate() }

        let settingsMode = app.segmentedControls["Settings mode"]
        guard settingsMode.waitForExistence(timeout: 5) else {
            throw XCTSkip(
                "The local macOS automation session did not expose the native Settings window.")
        }
        settingsMode.buttons.element(boundBy: 1).click()
        let engines = app.radioButtons["Engines"]
        XCTAssertTrue(engines.waitForExistence(timeout: 2))
        engines.click()

        XCTAssertTrue(
            app.popUpButtons["Batch transcription model"]
                .waitForExistence(timeout: 2))
        XCTAssertTrue(app.popUpButtons["Instant transcription model"].exists)
        XCTAssertTrue(app.popUpButtons["Instant latency"].exists)
        XCTAssertTrue(app.buttons["Expected speech languages"].exists)
        XCTAssertTrue(app.textFields["Recording context"].exists)
        XCTAssertTrue(app.checkBoxes["Show batch transcription progress"].exists)

        let batchPicker = app.popUpButtons["Batch transcription model"]
        batchPicker.click()
        app.menuItems["gpt-4o-mini-transcribe — Legacy"].click()
        XCTAssertTrue(app.staticTexts["Legacy batch model help"].exists)
    }
}
