import AppKit
import SwiftUI
import ServiceManagement

struct SettingsView: View {
    let keychain: KeychainStore
    @Bindable var settings: SettingsStore

    var body: some View {
        TabView {
            GeneralSettingsTab(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }
            EngineSettingsTab(keychain: keychain, settings: settings,
                              downloader: AppServices.shared.modelDownloader)
                .tabItem { Label("Engines", systemImage: "waveform") }
            StyleSettingsTab(settings: settings, history: AppServices.shared.history)
                .tabItem { Label("Style", systemImage: "textformat") }
        }
        .frame(width: 560, height: 480)
    }
}

private struct StyleSettingsTab: View {
    @Bindable var settings: SettingsStore
    let history: HistoryStore?

    @State private var overrides: [AppStyleOverride] = []
    @State private var newBundleID = ""
    @State private var newPreset: StylePreset = .neutral

    /// ISO-639-1 codes — sent to the ASR API verbatim; the cleanup prompt gets
    /// the English name via Locale (see AppServices wiring).
    private static let languages: [(name: String, code: String?)] = [
        ("Auto-detect", nil), ("English", "en"), ("German", "de"), ("French", "fr"),
        ("Spanish", "es"), ("Italian", "it"), ("Portuguese", "pt"), ("Dutch", "nl"),
        ("Polish", "pl"), ("Russian", "ru"), ("Ukrainian", "uk"), ("Turkish", "tr"),
        ("Japanese", "ja"), ("Korean", "ko"), ("Chinese", "zh"), ("Hindi", "hi"),
    ]

    var body: some View {
        Form {
            Section("Cleanup") {
                Picker("Cleanup level", selection: $settings.cleanupLevel) {
                    Text("None — raw transcript, no AI").tag("none")
                    Text("Light — punctuation only").tag("light")
                    Text("Medium — also remove fillers").tag("medium")
                    Text("High — also self-corrections, lists").tag("high")
                }
            }
            Section("Language") {
                Picker("Output language", selection: $settings.pinnedLanguage) {
                    ForEach(Self.languages, id: \.code) { language in
                        Text(language.name).tag(language.code)
                    }
                }
            }
            Section("Per-app style") {
                if overrides.isEmpty {
                    Text("No overrides — Talkie picks a tone from the app's category (chat: casual, email: polished, code: technical, otherwise neutral).")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(overrides, id: \.bundleID) { override in
                    HStack {
                        Text(override.bundleID)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Picker("", selection: presetBinding(for: override)) {
                            ForEach(StylePreset.allCases, id: \.self) { preset in
                                Text(preset.rawValue).tag(preset)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 120)
                        Button(role: .destructive) {
                            history?.removeStyleOverride(bundleID: override.bundleID)
                            reload()
                        } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                    }
                }
                HStack {
                    Menu(newBundleID.isEmpty ? "Choose app…" : newBundleID) {
                        ForEach(runningApps(), id: \.0) { bundleID, name in
                            Button("\(name) — \(bundleID)") { newBundleID = bundleID }
                        }
                    }
                    Picker("", selection: $newPreset) {
                        ForEach(StylePreset.allCases, id: \.self) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                    Button("Add") {
                        history?.setStyleOverride(bundleID: newBundleID, preset: newPreset)
                        newBundleID = ""
                        reload()
                    }
                    .disabled(newBundleID.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: reload)
    }

    private func reload() {
        overrides = history?.allStyleOverrides() ?? []
    }

    private func presetBinding(for override: AppStyleOverride) -> Binding<StylePreset> {
        Binding(
            get: { override.preset },
            set: { newValue in
                history?.setStyleOverride(bundleID: override.bundleID, preset: newValue)
                reload()
            })
    }

    /// Regular (Dock-visible) running apps as pick targets — covers the common case
    /// without a file-picker flow.
    private func runningApps() -> [(String, String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let id = app.bundleIdentifier else { return nil }
                return (id, app.localizedName ?? id)
            }
            .sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
    }
}

private struct GeneralSettingsTab: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Form {
            Section("Dictation") {
                LabeledContent("Hold to dictate") {
                    HStack {
                        Text("fn").foregroundStyle(.secondary)
                        ShortcutRecorderField(storage: $settings.pttShortcut)
                    }
                }
                LabeledContent("Hands-free toggle") {
                    HStack {
                        Text("double-tap fn").foregroundStyle(.secondary)
                        ShortcutRecorderField(storage: $settings.handsFreeShortcut)
                    }
                }
                LabeledContent("Paste last dictation", value: "⇧⌥V")
            }
            Section("Appearance") {
                Toggle("Show Flow Bar pill", isOn: $settings.showFlowBar)
                Toggle("Show Dock icon", isOn: $settings.showDockIcon)
            }
            Section("Privacy") {
                Toggle("Keep audio recordings", isOn: $settings.keepRecordings)
                Text("Off (default): audio is deleted after transcription. On: saved to Application Support/Talkie/Recordings.")
                    .font(.caption).foregroundStyle(.secondary)
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
    let downloader: ModelDownloader
    @State private var openAIKey: String = ""
    @State private var openRouterKey: String = ""

    private static let transcriptionPresets = ["gpt-4o-mini-transcribe", "gpt-4o-transcribe"] // whisper-1 retired from OpenAI's lineup

    var body: some View {
        Form {
            Section("Engine") {
                Picker("Transcription runs", selection: $settings.engineMode) {
                    Text("In the cloud (OpenAI)").tag("cloud")
                    Text("On this Mac (Parakeet)").tag("local")
                }
                .pickerStyle(.radioGroup)
            }
            Section("Local models") {
                switch downloader.state {
                case .ready:
                    LabeledContent("Status", value: "Downloaded")
                    removeModelsButton
                case .downloading:
                    ProgressView(value: downloader.progress) { Text("Downloading… \(Int(downloader.progress * 100))%") }
                case .failed(let message):
                    Text(message).foregroundStyle(.red)
                    Button("Retry") { Task { await downloader.download() } }
                case .idle:
                    LabeledContent("Status", value: FluidAudioBackend.modelsPresent ? "Downloaded" : "Not downloaded (~2 GB)")
                    if FluidAudioBackend.modelsPresent {
                        removeModelsButton
                    } else {
                        Button("Download models") { Task { await downloader.download() } }
                    }
                }
            }
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

    private var removeModelsButton: some View {
        Button("Remove models") {
            try? FileManager.default.removeItem(at: FluidAudioBackend.modelsDirectory)
            downloader.reset()
        }
    }
}
