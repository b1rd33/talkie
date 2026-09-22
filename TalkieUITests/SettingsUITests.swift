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

        let settingsMode = app.radioGroups["Settings mode"]
        guard settingsMode.waitForExistence(timeout: 5) else {
            XCTFail("The native Settings mode control was not exposed.")
            return
        }
        settingsMode.radioButtons["Advanced"].click()
        let engines = app.descendants(matching: .any)["Engines"].firstMatch
        XCTAssertTrue(engines.waitForExistence(timeout: 2))
        engines.click()

        XCTAssertTrue(
            app.popUpButtons["Batch transcription model"]
                .waitForExistence(timeout: 2))
        XCTAssertTrue(app.popUpButtons["Instant transcription model"].exists)
        XCTAssertTrue(app.popUpButtons["Instant latency"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["Expected speech languages"].exists)
        XCTAssertTrue(app.textFields["Recording context"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["Show batch transcription progress"].exists)

        let batchPicker = app.popUpButtons["Batch transcription model"]
        batchPicker.click()
        app.menuItems["gpt-4o-mini-transcribe — Legacy"].click()
        XCTAssertTrue(app.staticTexts["Legacy batch model help"].exists)
    }
    func testGeneralSettingsExposeOrbsGlassAndPermissionRepair() {
        let app = XCUIApplication()
        app.launchArguments = ["--e2e", "--e2e-session", UUID().uuidString,
                               "--e2e-scenario", "settings-model-controls"]
        app.launch()
        defer { app.terminate() }
        let modes = app.radioGroups["Settings mode"]
        XCTAssertTrue(modes.waitForExistence(timeout: 5))
        modes.radioButtons["Advanced"].click()
        app.descendants(matching: .any)["General"].firstMatch.click()
        XCTAssertTrue(app.buttons["Test microphone"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Show Talkie in Finder"].exists)
        let styles = app.popUpButtons["Pill style"]
        XCTAssertTrue(styles.exists)
        styles.click()
        XCTAssertTrue(app.menuItems["Thinking Orb — animated particles"].exists)
        XCTAssertTrue(app.menuItems["Liquid Glass — clear capsule"].exists)
        XCTAssertFalse(app.menuItems["Ink Line — a quiet, living line"].exists)
        XCTAssertFalse(app.menuItems["Calm Flow Ribbon — layered flowing lines"].exists)
        XCTAssertFalse(app.menuItems["Bare Wave — continuous organic waveform"].exists)
        app.menuItems["Thinking Orb — animated particles"].click()
    }
}
