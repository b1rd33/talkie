import SwiftData
import SwiftUI

@main
struct TalkieApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // Clear restoration left by the old, separate SwiftUI Settings window.
        SettingsSceneRestoration.clear()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
        } label: {
            MenuBarIcon(coordinator: AppServices.shared.coordinator)
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { AppServices.shared.showSettings() }
                    .keyboardShortcut(",")
            }
        }
    }
}

/// Menu-bar dropdown sharing the app's window and dictation actions.
struct MenuBarContent: View {
    @Bindable private var settings = AppServices.shared.settings
    private let coordinator = AppServices.shared.coordinator

    var body: some View {
        Text("Talkie — hold fn to dictate")
        Text("Transform selected text: ⇧⌥T").font(.caption)
        Divider()
        // The menu and Settings share the same engine preference.
        if settings.engineMode == "local" {
            Text(EngineError.localTranscriptionRemoved.errorDescription!)
        }
        Picker("Engine", selection: $settings.engineMode) {
            Text("Cloud (OpenAI)").tag("cloud")
            Text("Instant (OpenAI streaming)").tag("instant")
        }
        .pickerStyle(.inline)
        Picker("Language", selection: $settings.pinnedLanguage) {
            ForEach(SupportedLanguages.all, id: \.code) { language in
                Text(language.name).tag(language.code)
            }
        }
        Divider()
        Button("Copy last dictation") {
            guard let text = coordinator.lastResult?.cleanedText else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        .disabled(coordinator.lastResult == nil)
        Button("Undo last insertion") { _ = coordinator.undoLastInsertion() }
        Divider()
        Button("Open Talkie") {
            AppServices.shared.showHub()
        }
        Button("Settings…") { AppServices.shared.showSettings() }
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
        // Idle: Talkie's own waveform-bars glyph (template asset, auto-tinted).
        // Active states keep distinct SF symbols so state stays readable at a glance.
        switch coordinator.state {
        case .idle:
            Image("MenuBarIcon")
        case .recording:
            Image(systemName: "waveform.circle.fill")
        case .transcribing, .cleaning, .inserting:
            Image(systemName: "ellipsis.circle")
        case .error:
            Image(systemName: "exclamationmark.circle")
        }
    }
}
