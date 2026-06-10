import SwiftUI

struct SettingsView: View {
    let keychain: KeychainStore
    @Bindable var settings: SettingsStore

    @State private var openAIKey: String = ""
    @State private var openRouterKey: String = ""

    var body: some View {
        Form {
            Section("API Keys") {
                SecureField("OpenAI API key (sk-…)", text: $openAIKey)
                    .onChange(of: openAIKey) { _, new in keychain.write(new, for: .openAIKey) }
                SecureField("OpenRouter API key (sk-or-…)", text: $openRouterKey)
                    .onChange(of: openRouterKey) { _, new in keychain.write(new, for: .openRouterKey) }
            }
            Section("Models") {
                TextField("Transcription model", text: $settings.transcriptionModel)
                TextField("Cleanup model (OpenRouter)", text: $settings.cleanupModel)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 260)
        .onAppear {
            openAIKey = keychain.read(.openAIKey) ?? ""
            openRouterKey = keychain.read(.openRouterKey) ?? ""
        }
    }
}
