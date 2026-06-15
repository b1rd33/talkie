import XCTest
@testable import Talkie

final class SettingsSceneRestorationTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "talkie-tests-\(UUID().uuidString)")!
    }

    func testRemovesSwiftUISettingsRestorationKeys() {
        let defaults = makeDefaults()
        // Seed the exact keys macOS writes when it restores the Settings scene.
        defaults.set(0, forKey: "com_apple_SwiftUI_Settings_selectedTabIndex")
        defaults.set("0 0 560 568 0 0 1800 1169 ", forKey: "NSWindow Frame com_apple_SwiftUI_Settings_window")

        SettingsSceneRestoration.clear(in: defaults)

        XCTAssertNil(defaults.object(forKey: "com_apple_SwiftUI_Settings_selectedTabIndex"))
        XCTAssertNil(defaults.object(forKey: "NSWindow Frame com_apple_SwiftUI_Settings_window"))
    }

    func testLeavesUnrelatedDefaultsUntouched() {
        let defaults = makeDefaults()
        defaults.set("classic", forKey: "pillStyle")
        defaults.set(true, forKey: "showFlowBar")
        defaults.set("0 0 880 560 0 0 1800 1169 ", forKey: "NSWindow Frame com_apple_SwiftUI_hub_window")

        SettingsSceneRestoration.clear(in: defaults)

        XCTAssertEqual(defaults.string(forKey: "pillStyle"), "classic")
        XCTAssertTrue(defaults.bool(forKey: "showFlowBar"))
        XCTAssertNotNil(defaults.object(forKey: "NSWindow Frame com_apple_SwiftUI_hub_window"))
    }
}
