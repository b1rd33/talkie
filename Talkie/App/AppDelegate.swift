import AppKit
import AVFoundation
import ApplicationServices
import Foundation
import UserNotifications

@MainActor
final class AppServices {
    static let shared = AppServices()

    let keychain = KeychainStore()
    let settings = SettingsStore()
    let fnMonitor = FnKeyMonitor()
    let escMonitor = EscKeyMonitor()
    let recorder = AudioRecorder()
    let activeApp = ActiveAppMonitor()
    let shortcuts = ShortcutManager()
    let pasteLastInserter = TextInserter(notifier: Notifier())
    let coordinator: DictationCoordinator
    let history: HistoryStore?
    let modelDownloader = ModelDownloader(fetch: FluidAudioBackend.downloadModels)
    let licenseManager: LicenseManager
    let entitlements: EntitlementStore
    let onboarding = OnboardingWindow()
    private(set) var updater: UpdaterService?
    private(set) var flowBar: FlowBarPanel?

    private init() {
        let licenseKeychain = KeychainStore(service: "com.archiev.talkie.license")
        let license = LicenseManager(keychain: licenseKeychain)
        licenseManager = license
        let entitlementStore = EntitlementStore(
            license: license,
            trial: TrialManager(keychain: licenseKeychain))
        entitlements = entitlementStore
        let engine = OpenAIEngine(
            apiKeyProvider: { KeychainStore().read(.openAIKey) },
            modelProvider: { UserDefaults.standard.string(forKey: "transcriptionModel") ?? "gpt-4o-mini-transcribe" },
            languageProvider: { UserDefaults.standard.string(forKey: "pinnedLanguage") }
        )
        let cleanup = CleanupService(
            apiKeyProvider: {
                let provider = UserDefaults.standard.string(forKey: "cleanupProvider") ?? "openrouter"
                return KeychainStore().read(provider == "openai" ? .openAIKey : .openRouterKey)
            },
            modelProvider: { UserDefaults.standard.string(forKey: "cleanupModel") ?? "google/gemini-2.5-flash-lite" },
            endpointProvider: {
                let provider = UserDefaults.standard.string(forKey: "cleanupProvider") ?? "openrouter"
                return URL(string: provider == "openai"
                    ? "https://api.openai.com/v1/chat/completions"
                    : "https://openrouter.ai/api/v1/chat/completions")!
            },
            extraPayloadProvider: {
                let provider = UserDefaults.standard.string(forKey: "cleanupProvider") ?? "openrouter"
                let model = UserDefaults.standard.string(forKey: "cleanupModel") ?? ""
                // gpt-5-family reasoning models: skip the thinking pass (~1.3s saved).
                return (provider == "openai" && model.hasPrefix("gpt-5")) ? ["reasoning_effort": "none"] : [:]
            },
            customInstructionsProvider: {
                UserDefaults.standard.string(forKey: "customCleanupPrompt")
            }
        )
        let orTranscription = OpenRouterTranscriptionEngine(
            apiKeyProvider: { KeychainStore().read(.openRouterKey) },
            modelProvider: { UserDefaults.standard.string(forKey: "openrouterTranscriptionModel") ?? "mistralai/voxtral-mini-transcribe" }
        )
        let cloudSwitch = CloudEngineSwitch(openai: engine, openrouter: orTranscription)
        let backend = FluidAudioBackend()
        let localEngine = ParakeetEngine(backend: backend)
        let router = EngineRouter(
            cloud: cloudSwitch, local: localEngine,
            mode: { UserDefaults.standard.string(forKey: "engineMode") ?? "cloud" },
            localAvailable: { FluidAudioBackend.modelsPresent })
        let history = try? HistoryStore()
        self.history = history
        let activeApp = self.activeApp
        let notifier = Notifier()
        let resolver = StyleResolver(overrides: { [history] in
            history?.styleOverridesByBundleID() ?? [:]
        })
        coordinator = DictationCoordinator(
            recorder: recorder, engine: router, cleanup: cleanup,
            inserter: TextInserter(notifier: notifier),
            notifier: notifier, // Phase 2: cap + failure notifications
            history: history,
            frontmostApp: { activeApp.frontmost },
            dictionaryTermsProvider: { [history] in history?.dictionaryTermStrings() ?? [] },
            cleanupLevelProvider: {
                CleanupLevel(rawValue: UserDefaults.standard.string(forKey: "cleanupLevel") ?? "high") ?? .high
            },
            stylePresetProvider: { bundleID in resolver.resolve(bundleID: bundleID) },
            pinnedLanguageProvider: {
                // Settings stores the ISO code ("de"); the prompt wants a name ("German").
                UserDefaults.standard.string(forKey: "pinnedLanguage").flatMap {
                    Locale(identifier: "en").localizedString(forLanguageCode: $0)
                }
            },
            cleanupModelProvider: {
                // Stamped into DictationRecord.cleanupModel (spec §8) — same key CleanupService reads.
                UserDefaults.standard.string(forKey: "cleanupModel") ?? "google/gemini-2.5-flash-lite"
            },
            keepRecordingsProvider: {
                UserDefaults.standard.object(forKey: "keepRecordings") as? Bool ?? false
            },
            instantSkipCleanupProvider: {
                UserDefaults.standard.object(forKey: "instantSkipCleanup") as? Bool ?? false
            },
            entitlement: {
                entitlementStore.refresh() // keep the displayed `current` honest on every press
                return entitlementStore.gateError
            },
            liveSessionFactory: { [history] onPartial in
                guard UserDefaults.standard.string(forKey: "engineMode") == "instant" else {
                    throw EngineError.invalidResponse // coordinator treats factory throw as "no live session"
                }
                let key = KeychainStore().read(.openAIKey) ?? ""
                guard !key.isEmpty else { throw EngineError.missingAPIKey }
                // Same source as the batch path's dictionaryTermsProvider (Phase 4) — spec §3/§6
                // carries ASR-level vocabulary biasing and the pinned language into instant mode too.
                let terms = history?.dictionaryTermStrings() ?? []
                let session = OpenAIRealtimeSession(
                    transport: OpenAIRealtimeTransport(apiKey: key),
                    model: "gpt-realtime-whisper",
                    vocabulary: terms.isEmpty ? nil : terms.joined(separator: ", "),
                    language: UserDefaults.standard.string(forKey: "pinnedLanguage"), // nil = auto-detect
                    encoder: RealtimePCMEncoder(),
                    onPartial: onPartial)
                try await session.begin()
                return session
            })
    }

    /// First launch (or licensed-but-broken setup): show onboarding when there is
    /// no entitlement yet (never licensed AND trial never started) OR a required
    /// permission is missing (spec §7 / §9).
    func showOnboardingIfNeeded() {
        let needsEntitlement = !licenseManager.isLicensed && !entitlements.trialHasStarted
        let micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let axTrusted = AXIsProcessTrusted()
        guard needsEntitlement || !micGranted || !axTrusted else { return }
        showOnboarding()
    }

    /// Also reachable from Settings → General → "Run Setup Assistant…".
    func showOnboarding() {
        onboarding.show(entitlements: entitlements, keychain: keychain,
                        settings: settings, modelDownloader: modelDownloader)
    }

    private var pillReshowTask: Task<Void, Never>?

    /// "Hide for 1 hour": orders the pill out and re-shows it later, respecting
    /// whatever showFlowBar says by then. (If the user toggles showFlowBar in
    /// Settings during the hour, the Phase 2 visibility loop re-shows early —
    /// acceptable: an explicit settings change wins over a temporary hide.)
    func hidePillTemporarily(for seconds: TimeInterval = 3600) {
        pillReshowTask?.cancel()
        flowBar?.setVisible(false)
        pillReshowTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !Task.isCancelled else { return }
            self.flowBar?.setVisible(self.settings.showFlowBar)
        }
    }

    func startUI() {
        updater = UpdaterService()
        flowBar = FlowBarPanel(coordinator: coordinator, recorder: recorder,
                               settings: settings,
                               onHideForHour: { [weak self] in self?.hidePillTemporarily() },
                               onHidePermanently: { [weak self] in self?.settings.showFlowBar = false })
        fnMonitor.onPress = { [coordinator] in Task { await coordinator.dictationKeyPressed() } }
        fnMonitor.onRelease = { [coordinator] in Task { await coordinator.dictationKeyReleased() } }
        fnMonitor.onDoubleTap = { [coordinator] in Task { await coordinator.handsFreeToggled() } }
        fnMonitor.start()
        escMonitor.onEsc = { [coordinator] in coordinator.cancel() }
        trackDictationActivity()
        shortcuts.enablePasteLast { [coordinator] in
            guard let last = coordinator.lastResult?.cleanedText else { return }
            Task { try? await AppServices.shared.pasteLastInserter.insert(last) }
        }
        trackPillVisibility()
        trackCustomShortcuts()
        trackDockIconPolicy()
        trackPillPosition()
        trackPillActivity()
        showOnboardingIfNeeded()
    }

    private var pillFlashTask: Task<Void, Never>?

    /// Re-arming observation loop: panel existence + mouse participation follow
    /// the dictation state and pill style (PillVisibilityPolicy). After a
    /// completion, keeps the panel up ~1s so the checkmark flash stays visible.
    private func trackPillActivity() {
        _ = withObservationTracking {
            (coordinator.state, coordinator.lastCompletedAt)
        } onChange: { [weak self] in
            Task { @MainActor in self?.trackPillActivity() }
        }
        applyPillActivity()
    }

    /// Shared (non-observing) application of PillVisibilityPolicy.
    private func applyPillActivity() {
        let recentlyCompleted = coordinator.lastCompletedAt
            .map { Date().timeIntervalSince($0) < 1.0 } ?? false
        flowBar?.applyActivity(state: coordinator.state, recentlyCompleted: recentlyCompleted)
        pillFlashTask?.cancel()
        if recentlyCompleted {
            // Re-evaluate once the checkmark window closes so the panel orders out.
            pillFlashTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(1100))
                guard !Task.isCancelled else { return }
                self?.applyPillActivity()
            }
        }
    }

    /// Re-arming observation loop: pill placement follows Settings → Appearance.
    private func trackPillPosition() {
        _ = withObservationTracking {
            settings.pillPosition
        } onChange: { [weak self] in
            Task { @MainActor in self?.trackPillPosition() }
        }
        flowBar?.reposition()
    }

    /// Re-arming observation loop: Dock visibility follows Settings → Appearance.
    private func trackDockIconPolicy() {
        let show = withObservationTracking {
            settings.showDockIcon
        } onChange: { [weak self] in
            Task { @MainActor in self?.trackDockIconPolicy() }
        }
        NSApp.setActivationPolicy(show ? .regular : .accessory)
    }

    /// Re-arming observation loop: rebind custom combos whenever they change in Settings.
    private func trackCustomShortcuts() {
        withObservationTracking {
            rebindCustomShortcuts()
        } onChange: { [weak self] in
            Task { @MainActor in self?.trackCustomShortcuts() }
        }
    }

    private func rebindCustomShortcuts() {
        shortcuts.bindPushToTalk(settings.pttShortcut.flatMap(ShortcutSpec.init(storage:)),
                                 onPress: { [coordinator] in Task { await coordinator.dictationKeyPressed() } },
                                 onRelease: { [coordinator] in Task { await coordinator.dictationKeyReleased() } })
        shortcuts.bindHandsFree(settings.handsFreeShortcut.flatMap(ShortcutSpec.init(storage:)),
                                onToggle: { [coordinator] in Task { await coordinator.handsFreeToggled() } })
    }

    /// Re-arming observation loop: pill visibility follows Settings → Appearance.
    /// Applies through PillVisibilityPolicy (same as trackPillActivity) so the
    /// on/off toggle and pill style never fight the state-driven loop.
    private func trackPillVisibility() {
        _ = withObservationTracking {
            (settings.showFlowBar, settings.pillStyle)
        } onChange: { [weak self] in
            Task { @MainActor in self?.trackPillVisibility() }
        }
        flowBar?.refreshStyle() // deterministic re-render on style change
        applyPillActivity()
    }

    /// Re-arming observation loop: Esc monitoring runs only while a dictation is active.
    private func trackDictationActivity() {
        let active: Bool = withObservationTracking {
            switch coordinator.state {
            case .recording, .transcribing, .cleaning: true
            default: false
            }
        } onChange: { [weak self] in
            Task { @MainActor in self?.trackDictationActivity() }
        }
        active ? escMonitor.start() : escMonitor.stop()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self // harmless under tests
        guard !Self.isRunningTests else { return }
        AppServices.shared.startUI()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.content.userInfo["talkie.action"] as? String == "openEngineSettings" {
            NSApp.activate(ignoringOtherApps: true)
            // SwiftUI Settings has no public programmatic opener; this selector is the
            // established workaround on macOS 14 — verify it still resolves on the SDK you build with.
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        completionHandler()
    }
}
