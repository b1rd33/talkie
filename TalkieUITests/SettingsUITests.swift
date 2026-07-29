import XCTest

@MainActor
final class SettingsUITests: XCTestCase {
    func testAdvancedEnginesExposeTranscriptionControls() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--e2e",
            "--e2e-session", UUID().uuidString,
            "--e2e-scenario", "settings-model-controls",
        ]
        app.launch()
        defer { app.terminate() }

        app.activate()
        app.typeKey(",", modifierFlags: .command)

        let advanced = app.buttons["Advanced"]
        XCTAssertTrue(advanced.waitForExistence(timeout: 5))
        advanced.click()
        let engines = app.buttons["Engines"]
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
