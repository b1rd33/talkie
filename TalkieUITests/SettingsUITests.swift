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
            // This is a release gate: missing Settings coverage must fail, not
            // silently turn the UI job green. Log control identity, never values.
            for element in app.descendants(matching: .any).allElementsBoundByIndex {
                print("Settings control: \(element.elementType.rawValue) \(element.identifier) \(element.label)")
            }
            XCTFail("The native Settings mode control was not exposed.")
            return
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
