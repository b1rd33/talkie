import SwiftUI
import ServiceManagement

struct SettingsView: View {
    let keychain: KeychainStore
    @Bindable var settings: SettingsStore

    var body: some View {
        TabView {
            GeneralSettingsTab(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }
            EngineSettingsTab(keychain: keychain, settings: settings)
                .tabItem { Label("Engines", systemImage: "waveform") }
        }
        .frame(width: 520, height: 340)
    }
}

private struct GeneralSettingsTab: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Form {
            Section("Dictation") {
                LabeledContent("Hold to dictate", value: "fn")
                LabeledContent("Hands-free toggle", value: "double-tap fn")
                LabeledContent("Paste last dictation", value: "⇧⌥V")
                Text("Custom shortcuts arrive in a later update.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Appearance") {
                Toggle("Show Flow Bar pill", isOn: $settings.showFlowBar)
            }
            Section("Startup") {
                Toggle("Launch Talkie at login", isOn: $settings.launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                        } catch { NSLog("Talkie: launch-at-login failed: \(error)") }
                    }
            }
        }
        .formStyle(.grouped)
    }
}

private struct EngineSettingsTab: View {
    let keychain: KeychainStore
    @Bindable var settings: SettingsStore
    @State private var openAIKey: String = ""
    @State private var openRouterKey: String = ""

    private static let transcriptionPresets = ["gpt-4o-mini-transcribe", "gpt-4o-transcribe"] // whisper-1 retired from OpenAI's lineup

    var body: some View {
        Form {
            Section("API Keys") {
                SecureField("OpenAI API key (sk-…)", text: $openAIKey)
                    .onChange(of: openAIKey) { _, new in keychain.write(new, for: .openAIKey) }
                SecureField("OpenRouter API key (sk-or-…)", text: $openRouterKey)
                    .onChange(of: openRouterKey) { _, new in keychain.write(new, for: .openRouterKey) }
            }
            Section("Models") {
                Picker("Transcription model", selection: $settings.transcriptionModel) {
                    ForEach(Self.transcriptionPresets, id: \.self) { Text($0) }
                }
                TextField("Cleanup model (OpenRouter)", text: $settings.cleanupModel)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            openAIKey = keychain.read(.openAIKey) ?? ""
            openRouterKey = keychain.read(.openRouterKey) ?? ""
        }
    }
}
