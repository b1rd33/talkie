import SwiftUI
import AVFoundation
import ApplicationServices

enum OnboardingStep: Int, CaseIterable {
    // Talkie is free — no trial/license step. (TrialOrLicenseStep is kept below,
    // unused, so re-enabling paid licensing later is a one-line change.)
    case welcome, microphone, accessibility, fnKey, engineChoice, practice, done
}

struct OnboardingView: View {
    let entitlements: EntitlementStore
    let keychain: KeychainStore
    let settings: SettingsStore
    let modelDownloader: ModelDownloader
    var onFinished: () -> Void = {}

    @State private var step: OnboardingStep = .welcome

    var body: some View {
        VStack(spacing: 0) {
            stepBody
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(28)
            Divider()
            footer
        }
        .frame(width: 560, height: 460)
    }

    @ViewBuilder
    private var stepBody: some View {
        switch step {
        case .welcome:
            WelcomeStep()
        case .microphone:
            MicrophoneStep()
        case .accessibility:
            AccessibilityStep()
        case .fnKey:
            FnKeyStep()
        case .engineChoice:
            EngineChoiceStep(keychain: keychain, settings: settings, downloader: modelDownloader)
        case .practice:
            PracticeStep()
        case .done:
            DoneStep()
        }
    }

    private var footer: some View {
        HStack {
            if step != .welcome && step != .done {
                Button("Back") { back() }
            }
            Spacer()
            Text("Step \(step.rawValue + 1) of \(OnboardingStep.allCases.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if step == .done {
                Button("Start dictating") { onFinished() }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Continue") { next() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    }

    private func next() {
        if let nextStep = OnboardingStep(rawValue: step.rawValue + 1) { step = nextStep }
    }

    private func back() {
        if let previous = OnboardingStep(rawValue: step.rawValue - 1) { step = previous }
    }
}

// MARK: - Steps

private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Welcome to Talkie")
                .font(.largeTitle.bold())
            Text("Hold fn, speak naturally, release — polished text appears wherever your cursor is. A couple of permissions and you're dictating in two minutes.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TrialOrLicenseStep: View {
    let entitlements: EntitlementStore
    let advance: () -> Void

    @State private var keyInput = ""
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Try Talkie free for 14 days")
                .font(.title2.bold())
            switch entitlements.current {
            case .licensed:
                Label("Licensed — you're all set.", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Button("Continue") { advance() }
                    .buttonStyle(.borderedProminent)
            case .trial(let daysLeft):
                Label("Trial active — \(daysLeft) days left.", systemImage: "clock.fill")
                Button("Continue") { advance() }
                    .buttonStyle(.borderedProminent)
            case .expired:
                if entitlements.trialHasStarted {
                    Label("Your trial has ended — activate a license to keep dictating.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } else {
                    Text("Full-featured, no API keys of ours required — you bring your own. The trial starts only when you click the button.")
                        .foregroundStyle(.secondary)
                    Button("Start 14-day trial") {
                        entitlements.startTrial()
                        advance()
                    }
                    .buttonStyle(.borderedProminent)
                }
                Divider()
                Text("Already have a license key?")
                    .font(.headline)
                HStack {
                    TextField("XXXXX-XXXXX-XXXXX-XXXXX", text: $keyInput)
                        .font(.body.monospaced())
                        .autocorrectionDisabled()
                    Button("Activate") {
                        let result = entitlements.activate(
                            keyInput.trimmingCharacters(in: .whitespacesAndNewlines))
                        if result == .valid { advance() } else { errorText = result.message }
                    }
                    .disabled(keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Text("Machine ID: \(entitlements.machineID)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                if let errorText {
                    Text(errorText)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
        }
        .onAppear { entitlements.refresh() } // cached `current` may predate this re-run
    }
}

private struct MicrophoneStep: View {
    @State private var status = AVCaptureDevice.authorizationStatus(for: .audio)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Microphone access")
                .font(.title2.bold())
            Text("Talkie records only while you hold the dictation key. Audio is discarded right after transcription.")
                .foregroundStyle(.secondary)
            switch status {
            case .authorized:
                Label("Microphone access granted.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .notDetermined:
                Button("Allow microphone access") {
                    AVCaptureDevice.requestAccess(for: .audio) { _ in
                        Task { @MainActor in
                            status = AVCaptureDevice.authorizationStatus(for: .audio)
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            default: // .denied, .restricted
                Label("Microphone access denied.", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                HStack {
                    Button("Open System Settings") {
                        NSWorkspace.shared.open(URL(string:
                            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Check again") {
                        status = AVCaptureDevice.authorizationStatus(for: .audio)
                    }
                }
            }
        }
    }
}

private struct AccessibilityStep: View {
    @State private var trusted = AXIsProcessTrusted()
    private let poll = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Accessibility permission")
                .font(.title2.bold())
            Text("Needed to watch the fn key globally and paste text at your cursor. Talkie never reads your screen.")
                .foregroundStyle(.secondary)
            if trusted {
                Label("Accessibility granted.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label("Not granted yet.", systemImage: "hourglass")
                    .foregroundStyle(.orange)
                Button("Open System Settings") {
                    NSWorkspace.shared.open(URL(string:
                        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
                .buttonStyle(.borderedProminent)
                Text("Enable Talkie in the Accessibility list, then come back — this page updates by itself.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onReceive(poll) { _ in trusted = AXIsProcessTrusted() }
    }
}

private struct FnKeyStep: View {
    @State private var fnUsage = FnKeyStep.readFnUsage()

    /// com.apple.HIToolbox AppleFnUsageType: 0 = Do Nothing, 1 = Change Input
    /// Source, 2 = Show Emoji & Symbols, 3 = Start Dictation. Missing key =
    /// system default (treated as not-free).
    static func readFnUsage() -> Int {
        UserDefaults(suiteName: "com.apple.HIToolbox")?
            .object(forKey: "AppleFnUsageType") as? Int ?? 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Free up the fn key")
                .font(.title2.bold())
            Text("Set System Settings → Keyboard → “Press 🌐 key” to “Do Nothing”, so holding fn dictates instead of opening the emoji picker.")
                .foregroundStyle(.secondary)
            if fnUsage == 0 {
                Label("fn key is free — perfect.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label("The fn key is still assigned to a system action.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                HStack {
                    Button("Open Keyboard Settings") {
                        NSWorkspace.shared.open(URL(string:
                            "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Check again") { fnUsage = Self.readFnUsage() }
                }
            }
        }
    }
}

private struct EngineChoiceStep: View {
    let keychain: KeychainStore
    @Bindable var settings: SettingsStore
    let downloader: ModelDownloader

    @State private var openAIKey = ""
    @State private var openRouterKey = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose your engine")
                .font(.title2.bold())
            Picker("Transcription runs", selection: $settings.engineMode) {
                Text("In the cloud (OpenAI)").tag("cloud")
                Text("On this Mac (Parakeet)").tag("local")
            }
            .pickerStyle(.radioGroup)
            if settings.engineMode == "cloud" {
                SecureField("OpenAI API key (sk-…)", text: $openAIKey)
                    .onChange(of: openAIKey) { _, new in keychain.write(new, for: .openAIKey) }
                SecureField("OpenRouter API key for cleanup (sk-or-…)", text: $openRouterKey)
                    .onChange(of: openRouterKey) { _, new in keychain.write(new, for: .openRouterKey) }
                Text("Keys live in your Keychain and are used only from this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                switch downloader.state {
                case .ready:
                    Label("Local models downloaded.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .downloading:
                    ProgressView(value: downloader.progress) {
                        Text("Downloading models… \(Int(downloader.progress * 100))%")
                    }
                case .failed(let message):
                    Text(message).foregroundStyle(.red)
                    Button("Retry download") { Task { await downloader.download() } }
                case .idle:
                    if FluidAudioBackend.modelsPresent {
                        Label("Local models downloaded.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Download models (~2 GB)") { Task { await downloader.download() } }
                            .buttonStyle(.borderedProminent)
                    }
                }
                Text("Tip: add an OpenRouter key later for AI cleanup — without one, raw transcripts are inserted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            openAIKey = keychain.read(.openAIKey) ?? ""
            openRouterKey = keychain.read(.openRouterKey) ?? ""
        }
    }
}

private struct PracticeStep: View {
    @State private var practiceText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Try it")
                .font(.title2.bold())
            Text("Click into the box, hold fn, say something like “this is my first dictation um actually scratch that — Talkie is ready to go”, and release.")
                .foregroundStyle(.secondary)
            TextEditor(text: $practiceText)
                .font(.body)
                .frame(minHeight: 140)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
            Label("Hold fn while you speak — release to insert.", systemImage: "keyboard")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct DoneStep: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text("You're set")
                .font(.largeTitle.bold())
            Text("Talkie lives in your menu bar. Hold fn to dictate anywhere; double-tap fn for hands-free. Revisit this assistant anytime from Settings → General.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
