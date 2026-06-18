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
                    get: { profiles.selectedProfileID ?? DictationProfile.privateOffline.id },
                    set: { id in
                        guard let p = profiles.allProfiles.first(where: { $0.id == id }) else { return }
                        p.apply(to: settings)
                        profiles.select(p.id)
                    })) {
                    ForEach(profiles.allProfiles) { p in
                        Text(p.builtIn ? p.name : "\(p.name) (custom)").tag(p.id)
                    }
                }
                .labelsHidden()
                if let selected = profiles.selectedProfile {
                    Text(selected.simpleDescription).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("API key") { keyFields }

            Section("Output language") {
                Picker("Language", selection: Binding(
                    get: { settings.pinnedLanguage },
                    set: { settings.pinnedLanguage = $0 })) {
                    ForEach(SupportedLanguages.all, id: \.code) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }
                .labelsHidden()
                Text("Pin a language so the transcriber doesn't drift to the wrong one.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            openAIKey = keychain.read(.openAIKey) ?? ""
            openRouterKey = keychain.read(.openRouterKey) ?? ""
        }
    }

    @ViewBuilder private var keyFields: some View {
        let selected = profiles.selectedProfile
        // Local profiles need the on-device models; without them EngineRouter falls back
        // to the cloud (needing a key the profile claims none). Surface this for ANY
        // local profile, independent of requiredKey (covers local + cleanup too).
        let localModelsMissing = (selected?.engineMode == "local") && !FluidAudioBackend.modelsPresent
        if localModelsMissing {
            Label("On-device models aren't downloaded yet — run the Setup Assistant to enable offline mode (otherwise Talkie falls back to the cloud).",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange)
            Button("Open Setup Assistant…") { AppServices.shared.showOnboarding() }
        }
        switch selected?.requiredKey ?? .none {
        case .none:
            if !localModelsMissing {
                Label("No API key needed — runs on your Mac.", systemImage: "checkmark.seal")
                    .font(.caption).foregroundStyle(.green)
            }
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
