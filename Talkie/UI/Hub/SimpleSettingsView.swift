import AppKit
import SwiftUI

/// Simple mode: pick a profile in plain language, and Talkie shows only the API key
/// field(s) that profile actually needs (computed from `requiredKey`) — so you can't
/// land in an inconsistent state. Advanced mode (the tabbed view) has every knob.
struct SimpleSettingsView: View {
    let keychain: KeychainStore
    @Bindable var settings: SettingsStore
    let profiles: ProfileStore

    @State private var openAIKey = ""
    @State private var openRouterKey = ""

    var body: some View {
        Form {
            Section("What do you want?") {
                Picker("Mode", selection: Binding(
                    get: { profiles.selectedProfileID },
                    set: { id in
                        guard let p = profiles.allProfiles.first(where: { $0.id == id }) else { return }
                        p.apply(to: settings)
                        profiles.select(p.id)
                    })) {
                    Text("Choose a cloud profile").tag(Optional<UUID>.none)
                    ForEach(profiles.allProfiles) { p in
                        Text(p.displaySummary).tag(Optional(p.id))
                    }
                }
                .labelsHidden()
                if let selected = profiles.selectedProfile {
                    Text(selected.simpleDescription).font(.caption).foregroundStyle(.secondary)
                }
                Text(activeModelSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("API key") { keyFields }

            SpeakerFilteringSettingsSection(
                settings: settings,
                speakerReference: AppServices.shared.speakerReference)

            Section("Output / cleanup language") {
                Picker("Output language", selection: Binding(
                    get: { settings.pinnedLanguage },
                    set: { settings.pinnedLanguage = $0 })) {
                    ForEach(SupportedLanguages.all, id: \.code) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }
                .labelsHidden()
                Text("Controls cleanup and output language. Speech-recognition hints are in Advanced → Engines.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Microphone") {
                MicrophoneCheckView(settings: settings)
            }

            Section("Permissions") {
                PermissionSettingsRows(permissions: AppServices.shared.permissions)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            openAIKey = keychain.read(.openAIKey) ?? ""
            openRouterKey = keychain.read(.openRouterKey) ?? ""
            AppServices.shared.permissions.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            AppServices.shared.permissions.refresh()
        }
    }

    private var activeModelSummary: String {
        switch settings.engineMode {
        case "instant":
            return "Live model: \(settings.realtimeTranscriptionModel)"
        case "local":
            return EngineError.localTranscriptionRemoved.errorDescription!
        default:
            let model = settings.transcriptionProvider == "openrouter"
                ? settings.openrouterTranscriptionModel
                : settings.transcriptionModel
            return "Batch model: \(model)"
        }
    }

    @ViewBuilder private var keyFields: some View {
        let selected = profiles.selectedProfile
        switch selected?.requiredKey ?? .none {
        case .none:
            Text("Choose a cloud profile and add its API key to use dictation.")
                .font(.caption).foregroundStyle(.secondary)
        case .openAI:
            openAIField
        case .openRouter:
            openRouterField
        case .both:
            openAIField
            openRouterField
            Text("This profile uses both providers.").font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var openAIField: some View {
        SecureField("OpenAI API key (sk-…)", text: $openAIKey)
            .onChange(of: openAIKey) { _, new in keychain.write(new, for: .openAIKey) }
        if openAIKey.isEmpty {
            Label("Add your OpenAI key or dictation won't work.", systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange)
        }
    }

    @ViewBuilder private var openRouterField: some View {
        SecureField("OpenRouter API key (sk-or-…)", text: $openRouterKey)
            .onChange(of: openRouterKey) { _, new in keychain.write(new, for: .openRouterKey) }
        if openRouterKey.isEmpty {
            Label("Add your OpenRouter key or dictation won't work.", systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange)
        }
    }
}
