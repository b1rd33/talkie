import SwiftUI

@main
struct TalkieApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Talkie", systemImage: menuIcon) {
            Text("Talkie — hold fn to dictate")
            Picker("Engine", selection: Binding(
                get: { AppServices.shared.settings.engineMode },
                set: { AppServices.shared.settings.engineMode = $0 })) {
                Text("Cloud").tag("cloud")
                Text("Local").tag("local")
            }
            .pickerStyle(.inline)
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

    private var menuIcon: String {
        switch AppServices.shared.coordinator.state {
        case .idle: "waveform.circle"
        case .recording: "waveform.circle.fill"
        case .transcribing, .cleaning, .inserting: "ellipsis.circle"
        case .error: "exclamationmark.circle"
        }
    }
}
