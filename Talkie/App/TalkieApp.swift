import SwiftUI

@main
struct TalkieApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Talkie", systemImage: "waveform.circle") {
            Text("Talkie — hold fn to dictate")
            Divider()
            SettingsLink { Text("Settings…") }
                .keyboardShortcut(",")
            Button("Quit Talkie") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        Settings {
            SettingsView(keychain: AppServices.shared.keychain,
                         settings: AppServices.shared.settings)
        }
    }
}
