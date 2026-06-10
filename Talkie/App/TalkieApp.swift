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
            Text("Settings placeholder") // replaced in Task 3
                .frame(width: 420, height: 200)
        }
    }
}
