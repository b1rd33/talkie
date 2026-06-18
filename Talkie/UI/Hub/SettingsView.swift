import AppKit
import SwiftUI
import ServiceManagement

struct SettingsView: View {
    let keychain: KeychainStore
    @Bindable var settings: SettingsStore

    var body: some View {
        VStack(spacing: 0) {
            Picker("Settings mode", selection: $settings.simpleMode) {
                Text("Simple").tag(true)
                Text("Advanced").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)
            .padding(8)
            Divider()
            if settings.simpleMode {
                SimpleSettingsView(keychain: keychain, settings: settings,
                                   profiles: AppServices.shared.profiles)
            } else {
                devTabs
            }
        }
        .frame(width: 560, height: 480)
    }

    private var devTabs: some View {
        TabView {
            ProfilesSettingsTab(settings: settings, profiles: AppServices.shared.profiles)
                .tabItem { Label("Profiles", systemImage: "person.crop.circle") }
            GeneralSettingsTab(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }
            EngineSettingsTab(keychain: keychain, settings: settings,
                              downloader: AppServices.shared.modelDownloader)
                .tabItem { Label("Engines", systemImage: "waveform") }
            StyleSettingsTab(settings: settings, history: AppServices.shared.history)
                .tabItem { Label("Style", systemImage: "textformat") }
            // Talkie is free — no License tab. (LicenseSettingsTab kept in the
            // codebase so paid licensing can be re-enabled later.)
        }
    }
}

/// The cleanup controls are inert when instant mode is inserting raw streamed
/// text. Single source of truth shared by the Engine and Style tabs so they
/// can't drift. (Part B widens this to also cover live typing.)
func cleanupInactive(_ s: SettingsStore) -> Bool {
    s.engineMode == "instant" && (s.instantSkipCleanup || s.instantLiveType)
}

/// Profile picker: selecting a profile applies its whole pipeline (engine + providers
/// + models + cleanup) as one consistent unit, so the invalid mixes (e.g. OpenAI
/// provider + an OpenRouter-prefixed model) can't happen. Built-ins + custom profiles.
private struct ProfilesSettingsTab: View {
    @Bindable var settings: SettingsStore
    let profiles: ProfileStore
    @State private var showSaveAs = false
    @State private var newName = ""

    var body: some View {
        Form {
            Section("Profile") {
                Picker("Active profile", selection: Binding(
                    get: { profiles.selectedProfileID ?? DictationProfile.privateOffline.id },
                    set: { id in
                        guard let p = profiles.allProfiles.first(where: { $0.id == id }) else { return }
                        p.apply(to: settings) // writes the whole pipeline consistently
                        profiles.select(p.id)
                    })) {
                    ForEach(profiles.allProfiles) { p in
                        Text(p.builtIn ? p.name : "\(p.name) (custom)").tag(p.id)
                    }
                }
                if let selected = profiles.selectedProfile {
                    Label(Self.keyText(selected.requiredKey), systemImage: "key")
                        .font(.caption).foregroundStyle(.secondary)
                    if isModified(from: selected) {
                        HStack {
                            Text("Modified from “\(selected.name)”.")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Reapply") { selected.apply(to: settings) }
                        }
                    }
                }
            }
            Section {
                HStack {
                    Button("Save as new profile…") { newName = ""; showSaveAs = true }
                    if let selected = profiles.selectedProfile, !selected.builtIn {
                        Button("Save") { profiles.saveCurrentSettingsToSelected(from: settings) }
                            .disabled(!isModified(from: selected))
                        Spacer()
                        Button("Delete", role: .destructive) {
                            profiles.delete(selected.id)
                            profiles.selectedProfile?.apply(to: settings) // keep live settings in sync with the fallback
                        }
                    }
                }
            }
            Section {
                Text("Picking a profile sets the engine, transcription, and cleanup together as a known-good combination. Fine-tune in the other tabs, then Save into a custom profile or Reapply to reset. Built-in profiles can't be edited or deleted.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .alert("Save as new profile", isPresented: $showSaveAs) {
            TextField("Profile name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { profiles.saveAsNewProfile(named: newName, from: settings) }
        }
    }

    /// True when live settings have drifted from the selected profile's pipeline.
    private func isModified(from selected: DictationProfile) -> Bool {
        !DictationProfile(snapshot: settings).samePipeline(as: selected)
    }

    private static func keyText(_ key: RequiredKey) -> String {
        switch key {
        case .none: "No API key needed — runs on-device."
        case .openAI: "Needs your OpenAI key."
        case .openRouter: "Needs your OpenRouter key."
        case .both: "Needs both your OpenAI and OpenRouter keys."
        }
    }
}

private struct StyleSettingsTab: View {
    @Bindable var settings: SettingsStore
    let history: HistoryStore?

    @State private var overrides: [AppStyleOverride] = []
    @State private var newBundleID = ""
    @State private var newPreset: StylePreset = .neutral

    var body: some View {
        Form {
            Section("Cleanup") {
                Picker("Cleanup level", selection: $settings.cleanupLevel) {
                    Text("None — raw transcript, no AI").tag("none")
                    Text("Light — punctuation only").tag("light")
                    Text("Medium — also remove fillers").tag("medium")
                    Text("High — also self-corrections, lists").tag("high")
                    Text("Custom — your own instructions").tag("custom")
                }
                .disabled(cleanupInactive(settings))
                if settings.cleanupLevel == "custom" {
                    TextEditor(text: $settings.customCleanupPrompt)
                        .font(.body)
                        .frame(minHeight: 70)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
                        .disabled(cleanupInactive(settings))
                    Text("Tell the AI exactly how to rewrite your dictation (e.g. “summarize into action items”, “translate to English”). Output-only guardrails stay in place; empty = High.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if cleanupInactive(settings) {
                    Text("Inactive — instant mode is set to insert raw text without cleanup.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Language") {
                Picker("Output language", selection: $settings.pinnedLanguage) {
                    ForEach(SupportedLanguages.all, id: \.code) { language in
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
                Picker("Pill style", selection: $settings.pillStyle) {
                    Text("Bare waveform — chromeless, dots when idle").tag(PillStyle.bareWaveform)
                    Text("Dynamic Island — docked top-center").tag(PillStyle.dynamicIsland)
                    Text("Frosted glass — translucent capsule").tag(PillStyle.frostedGlass)
                    Text("Hidden — appears only while dictating").tag(PillStyle.hidden)
                }
                Picker("Pill position", selection: $settings.pillPosition) {
                    Text("Bottom center").tag("bottomCenter")
                    Text("Bottom left").tag("bottomLeft")
                    Text("Bottom right").tag("bottomRight")
                    Text("Top center").tag("topCenter")
                }
                Toggle("Show Dock icon", isOn: $settings.showDockIcon)
            }
            Section("Privacy") {
                Toggle("Keep audio recordings", isOn: $settings.keepRecordings)
                Text("Off (default): audio is deleted after transcription. On: saved to Application Support/Talkie/Recordings.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Setup") {
                Button("Run Setup Assistant…") {
                    AppServices.shared.showOnboarding()
                }
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

    private static let transcriptionPresets = ModelPresets.transcription // shared source of truth (whisper-1 retired)

    var body: some View {
        Form {
            Section("Engine") {
                Picker("Transcription runs", selection: $settings.engineMode) {
                    Text("Cloud — batch (≈ $0.18/hr)").tag("cloud")
                    Text("Cloud — instant streaming (≈ $1.02/hr)").tag("instant")
                    Text("On this Mac — free, offline").tag("local")
                }
                .pickerStyle(.radioGroup)
                Text("Instant streams audio while you speak (gpt-4o-mini-transcribe, billed per audio minute) so text lands ~1s after release. Batch waits until release (gpt-4o transcribe models).")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Skip cleanup in instant mode (fastest)", isOn: $settings.instantSkipCleanup)
                    .disabled(settings.engineMode != "instant" || settings.instantLiveType)
                Text("Inserts the raw streamed text immediately, with no cleanup pass.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Type live into the app while speaking", isOn: $settings.instantLiveType)
                    .disabled(settings.engineMode != "instant")
                Text("Types raw text as you speak — skips cleanup. Needs Accessibility access.")
                    .font(.caption).foregroundStyle(.secondary)
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
                Picker("Cloud transcription via", selection: $settings.transcriptionProvider) {
                    Text("OpenAI").tag("openai")
                    Text("OpenRouter").tag("openrouter")
                }
                if settings.transcriptionProvider == "openrouter" {
                    HStack {
                        TextField("OpenRouter transcription model", text: $settings.openrouterTranscriptionModel)
                        Menu("Presets") {
                            Button("openai/whisper-large-v3-turbo — $0.0007/min, 99+ languages, fastest") {
                                settings.openrouterTranscriptionModel = "openai/whisper-large-v3-turbo"
                            }
                            Button("nvidia/parakeet-tdt-0.6b-v3 — $0.0015/min, best EU-language accuracy") {
                                settings.openrouterTranscriptionModel = "nvidia/parakeet-tdt-0.6b-v3"
                            }
                            Button("mistralai/voxtral-mini-transcribe — $0.003/min") {
                                settings.openrouterTranscriptionModel = "mistralai/voxtral-mini-transcribe"
                            }
                            Button("microsoft/mai-transcribe-1.5 — $0.006/min, 100+ locales") {
                                settings.openrouterTranscriptionModel = "microsoft/mai-transcribe-1.5"
                            }
                            Button("google/chirp-3 — $0.016/min, widest language preview") {
                                settings.openrouterTranscriptionModel = "google/chirp-3"
                            }
                        }
                        .frame(width: 90)
                    }
                    Text("Uses your OpenRouter key. Instant mode stays OpenAI-only (realtime websocket).")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Picker("Transcription model", selection: $settings.transcriptionModel) {
                        ForEach(Self.transcriptionPresets, id: \.self) { Text($0) }
                    }
                }
            }
            Section("Cleanup") {
                if cleanupInactive(settings) {
                    Text("Disabled — instant mode is inserting raw streamed text.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Picker("Cleanup runs via", selection: $settings.cleanupProvider) {
                    Text("OpenRouter").tag("openrouter")
                    Text("OpenAI (direct)").tag("openai")
                }
                .disabled(cleanupInactive(settings))
                HStack {
                    TextField("Cleanup model", text: $settings.cleanupModel)
                    Menu("Presets") {
                        if settings.cleanupProvider == "openai" {
                            Button("gpt-5.4-nano — fastest (~0.7s)") { setCleanup("gpt-5.4-nano") }
                            Button("gpt-5.4-mini — higher quality") { setCleanup("gpt-5.4-mini") }
                            Button("gpt-4.1-nano — non-reasoning") { setCleanup("gpt-4.1-nano") }
                        } else {
                            Button("google/gemini-2.5-flash-lite — fastest (~0.4s)") { setCleanup("google/gemini-2.5-flash-lite") }
                            Button("google/gemini-2.5-flash — balanced (~1.3s)") { setCleanup("google/gemini-2.5-flash") }
                            Button("openai/gpt-5.4-nano — via OpenRouter") { setCleanup("openai/gpt-5.4-nano") }
                        }
                    }
                    .frame(width: 90)
                }
                .disabled(cleanupInactive(settings))
                Text(settings.cleanupProvider == "openai"
                     ? "Uses your OpenAI key. gpt-5-family models automatically skip the reasoning pass for speed."
                     : "Uses your OpenRouter key. Latencies measured live on this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
                if !cleanupInactive(settings),
                   let warning = CleanupCredentialWarning.message(
                    cleanupProvider: settings.cleanupProvider,
                    cleanupModel: settings.cleanupModel,
                    hasOpenAIKey: !openAIKey.isEmpty,
                    hasOpenRouterKey: !openRouterKey.isEmpty) {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            openAIKey = keychain.read(.openAIKey) ?? ""
            openRouterKey = keychain.read(.openRouterKey) ?? ""
        }
    }

    private func setCleanup(_ model: String) {
        settings.cleanupModel = model
    }

    private var removeModelsButton: some View {
        Button("Remove models") {
            try? FileManager.default.removeItem(at: FluidAudioBackend.modelsDirectory)
            downloader.reset()
        }
    }
}
