import SwiftData
import SwiftUI

@main
struct TalkieApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
        } label: {
            MenuBarIcon(coordinator: AppServices.shared.coordinator)
        }
        Window("Talkie", id: "hub") {
            if let history = AppServices.shared.history {
                HubView(history: history)
                    .modelContainer(history.container) // @Query in Tasks 7–8 reads this
            } else {
                HubView(history: nil)
            }
        }
        .defaultSize(width: 880, height: 560)
        Settings {
            SettingsView(keychain: AppServices.shared.keychain,
                         settings: AppServices.shared.settings)
        }
    }
}

/// Menu-bar dropdown. Lives in its own View so @Environment(\.openWindow) resolves.
struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow
    @Bindable private var settings = AppServices.shared.settings

    var body: some View {
        Text("Talkie — hold fn to dictate")
        Divider()
        // spec §7: the menu carries the Cloud/Local engine picker too — bound to
        // the same SettingsStore property the Engines tab's radio group uses (Phase 3).
        Picker("Engine", selection: $settings.engineMode) {
            Text("Cloud (OpenAI)").tag("cloud")
            Text("On this Mac (Parakeet)").tag("local")
        }
        .pickerStyle(.inline)
        Divider()
        Button("Open Talkie") {
            openWindow(id: "hub")
            // LSUIElement apps don't auto-activate; without this the hub opens behind others.
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Check for Updates…") { AppServices.shared.updater?.checkForUpdates() }
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Divider()
        Button("Quit Talkie") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// Menu-bar glyph that re-renders on coordinator state changes. Reading the state
/// inside this View's body registers Observation tracking — the Phase 1
/// computed-property-in-App approach did not re-render reliably.
struct MenuBarIcon: View {
    let coordinator: DictationCoordinator

    var body: some View {
        Image(systemName: symbolName)
    }

    private var symbolName: String {
        switch coordinator.state {
        case .idle: "waveform.circle"
        case .recording: "waveform.circle.fill"
        case .transcribing, .cleaning, .inserting: "ellipsis.circle"
        case .error: "exclamationmark.circle"
        }
    }
}
