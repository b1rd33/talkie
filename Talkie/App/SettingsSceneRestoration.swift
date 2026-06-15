import Foundation

/// Strips the persisted SwiftUI `Settings{}` scene restoration state.
///
/// Bug 2026-06: macOS restores the Settings window at every launch and the
/// restored "Pill style" Picker re-emits its stale selection through
/// `$settings.pillStyle`, whose `didSet` writes it back to UserDefaults —
/// silently overwriting whatever style the user picked. Removing these keys
/// before the scene is built stops the Settings window from auto-restoring, so
/// no restored control can replay a value at launch.
enum SettingsSceneRestoration {
    /// Keys AppKit/SwiftUI persist for the Settings scene's window + selected tab.
    static let restorationKeys = [
        "com_apple_SwiftUI_Settings_selectedTabIndex",
        "NSWindow Frame com_apple_SwiftUI_Settings_window",
    ]

    static func clear(in defaults: UserDefaults = .standard) {
        for key in restorationKeys {
            defaults.removeObject(forKey: key)
        }
    }
}
