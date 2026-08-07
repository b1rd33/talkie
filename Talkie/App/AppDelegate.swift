import AppKit
import AVFoundation
import ApplicationServices
import Foundation
import OSLog
import SwiftUI
import UserNotifications

@MainActor
final class AppServices {
    static let shared = AppServices(environment: .launch())
    private static let diagnosticsLogger = Logger(
        subsystem: "com.archiev.talkie",
        category: "Dictation")

    // Must precede SettingsStore/ProfileStore: both may persist defaults during
    // initialization, while setup migration needs the pre-initialization domain.
    let environment: AppEnvironment
    let setupState: SetupStateStore
    let keychain: KeychainStore
    let settings: SettingsStore
    let profiles: ProfileStore
    let fnMonitor: FnKeyMonitor
    let escMonitor: EscKeyMonitor
    let recorder: AudioRecorder
    let speakerReference: SpeakerReferenceController
    let activeApp: ActiveAppMonitor
    let contextReader: FocusedContextReader
    let shortcuts: ShortcutManager
    let permissions: PermissionManager
    let notifier: Notifier
    let pasteLastInserter: TextInserter
    let coordinator: DictationCoordinator
    let history: HistoryStore?
    let modelDownloader: ModelDownloader
    let onboarding: OnboardingWindow
    let selectionTransforms: SelectionTransformCoordinator
    let selectionTransformWindow: SelectionTransformWindow
    private(set) var flowBar: FlowBarPanel?
#if DEBUG
    private var e2eBridge: E2ETestControlBridge?
    private var screenshotDemoPill: ScreenshotDemoPillPanel?
#endif

    init(environment: AppEnvironment) {
        self.environment = environment
        let defaults = environment.defaults
        // Preserve this construction order: setup migration inspects the domain
        // before SettingsStore persists any normalized defaults.
        let setupState = SetupStateStore(defaults: defaults)
        let keychain = KeychainStore(service: environment.keychainService)
        let settings = SettingsStore(defaults: defaults)
        let profiles = ProfileStore(defaults: defaults)
        let fnMonitor = FnKeyMonitor()
        let escMonitor = EscKeyMonitor()
        let recorder = AudioRecorder(preferredDeviceUID: {
            defaults.string(forKey: "preferredAudioDeviceUID")
        })
        let speakerReference = SpeakerReferenceController()
        let activeApp = ActiveAppMonitor()
        let contextReader = FocusedContextReader()
        let shortcuts = ShortcutManager()
        let permissions = PermissionManager()
        let notifier = Notifier()
        let pasteLastInserter = TextInserter(notifier: notifier)
        let modelDownloader = ModelDownloader(fetch: FluidAudioBackend.downloadModels)
        let onboarding = OnboardingWindow()

        let credentialOverrides = environment.credentialOverrides
        let credential: @Sendable (KeychainStore.Key) -> String? = { key in
            credentialOverrides[key] ?? keychain.read(key)
        }
        let engine = OpenAIEngine(
            apiKeyProvider: { credential(.openAIKey) },
            modelProvider: { defaults.string(forKey: "transcriptionModel") ?? "gpt-transcribe" },
            contextProvider: { dictionaryTerms in
                TranscriptionContext.build(
                    prompt: defaults.string(forKey: "transcriptionContextPrompt") ?? "",
                    dictionaryTerms: dictionaryTerms,
                    languageCodes:
                        defaults.stringArray(forKey: "expectedInputLanguages") ?? [])
            },
            streamProvider: {
                defaults.object(forKey: "streamBatchTranscription") as? Bool ?? true
            },
            speakerFilterProvider: {
                guard defaults.object(forKey: "speakerFilteringEnabled") as? Bool ?? false
                else { return nil }
                return try? speakerReference.store.configuration()
            },
            speakerFilteringEnabledProvider: {
                defaults.object(forKey: "speakerFilteringEnabled") as? Bool ?? false
            }
        )
        let cleanup = CleanupService(
            apiKeyProvider: {
                let provider = defaults.string(forKey: "cleanupProvider") ?? "openrouter"
                return credential(provider == "openai" ? .openAIKey : .openRouterKey)
            },
            modelProvider: { defaults.string(forKey: "cleanupModel") ?? "google/gemini-2.5-flash-lite" },
            endpointProvider: {
                let provider = defaults.string(forKey: "cleanupProvider") ?? "openrouter"
                return URL(string: provider == "openai"
                    ? "https://api.openai.com/v1/chat/completions"
                    : "https://openrouter.ai/api/v1/chat/completions")!
            },
            extraPayloadProvider: {
                let provider = defaults.string(forKey: "cleanupProvider") ?? "openrouter"
                let model = defaults.string(forKey: "cleanupModel") ?? ""
                // gpt-5-family reasoning models: skip the thinking pass (~1.3s saved).
                return (provider == "openai" && model.hasPrefix("gpt-5")) ? ["reasoning_effort": "none"] : [:]
            },
            customInstructionsProvider: {
                defaults.string(forKey: "customCleanupPrompt")
            }
        )
        let selectionTransformer = LLMSelectionTransformer(
            apiKeyProvider: {
                let provider = defaults.string(forKey: "cleanupProvider") ?? "openrouter"
                return credential(provider == "openai" ? .openAIKey : .openRouterKey)
            },
            modelProvider: { defaults.string(forKey: "cleanupModel") ?? "google/gemini-2.5-flash-lite" },
            endpointProvider: {
                URL(string: (defaults.string(forKey: "cleanupProvider") ?? "openrouter") == "openai"
                    ? "https://api.openai.com/v1/chat/completions"
                    : "https://openrouter.ai/api/v1/chat/completions")!
            },
            extraPayloadProvider: {
                let provider = defaults.string(forKey: "cleanupProvider") ?? "openrouter"
                let model = defaults.string(forKey: "cleanupModel") ?? ""
                return provider == "openai" && model.hasPrefix("gpt-5")
                    ? ["reasoning_effort": "none"] : [:]
            })
        let selectionTransforms = SelectionTransformCoordinator(transformer: selectionTransformer)
        let selectionTransformWindow = SelectionTransformWindow()
        let orTranscription = OpenRouterTranscriptionEngine(
            apiKeyProvider: { credential(.openRouterKey) },
            modelProvider: { defaults.string(forKey: "openrouterTranscriptionModel") ?? "mistralai/voxtral-mini-transcribe" }
        )
        let cloudSwitch = CloudEngineSwitch(
            openai: engine,
            openrouter: orTranscription,
            provider: {
                if defaults.object(forKey: "speakerFilteringEnabled") as? Bool ?? false {
                    return "openai"
                }
                return defaults.string(forKey: "transcriptionProvider") ?? "openai"
            })
        let backend = FluidAudioBackend()
        let localEngine = ParakeetEngine(backend: backend)
        let router = EngineRouter(
            cloud: cloudSwitch, local: localEngine,
            mode: {
                if defaults.object(forKey: "speakerFilteringEnabled") as? Bool ?? false {
                    return "cloud"
                }
                return defaults.string(forKey: "engineMode") ?? "cloud"
            },
            localAvailable: { FluidAudioBackend.modelsPresent })
        let history = try? HistoryStore(inMemory: environment.historyInMemory)
        let resolver = StyleResolver(overrides: { [history] in
            history?.styleOverridesByBundleID() ?? [:]
        })
        let sessionResolver = DictationSessionConfigurationResolver(
            settings: settings,
            profileID: { profiles.selectedProfileID },
            dictionaryTerms: { [history] in history?.dictionaryTermStrings() ?? [] },
            dictionaryPromptTerms: { [history] in history?.dictionaryPromptTerms() ?? [] },
            snippets: { [history] in history?.snippetExpansions() ?? [] },
            focusedContext: {
                let target = activeApp.frontmost.bundleID
                guard ContextPolicy.mayRead(
                    enabled: settings.contextAwarenessEnabled,
                    bundleID: target,
                    exclusions: settings.contextExcludedBundleIDs) else { return nil }
                return contextReader.read()
            },
            style: { bundleID in resolver.resolve(bundleID: bundleID) },
            speakerFilter: { try? speakerReference.store.configuration() })

        let configuredTranscriptionEngine: (DictationSessionConfiguration) -> any TranscriptionEngine = { configuration in
            let transcription = configuration.transcription
            let openAI = OpenAIEngine(
                apiKeyProvider: { credential(.openAIKey) },
                modelProvider: { transcription.openAIModel },
                contextProvider: { dictionaryTerms in
                    TranscriptionContext.build(
                        prompt: transcription.contextPrompt,
                        dictionaryTerms: dictionaryTerms,
                        languageCodes: transcription.expectedLanguageCodes)
                },
                streamProvider: { transcription.streamBatch },
                speakerFilterProvider: { transcription.speakerFilter },
                speakerFilteringEnabledProvider: {
                    transcription.speakerFilteringRequested
                })
            let openRouter = OpenRouterTranscriptionEngine(
                apiKeyProvider: { credential(.openRouterKey) },
                modelProvider: { transcription.openRouterModel })
            let cloud = CloudEngineSwitch(
                openai: openAI,
                openrouter: openRouter,
                provider: { transcription.provider.rawValue })
            // `.localOnly` is deliberately resolved to local regardless of any
            // later settings mutation; EngineRouter never cloud-falls-back in local mode.
            return EngineRouter(
                cloud: cloud,
                local: localEngine,
                configuration: configuration,
                localAvailable: { FluidAudioBackend.modelsPresent })
        }

        let configuredCleanupService: (DictationSessionConfiguration) -> any CleanupServicing = { configuration in
            let cleanup = configuration.cleanup
            return CleanupService(
                apiKeyProvider: {
                    credential(cleanup.provider == .openAI ? .openAIKey : .openRouterKey)
                },
                modelProvider: { cleanup.model },
                endpointProvider: {
                    URL(string: cleanup.provider == .openAI
                        ? "https://api.openai.com/v1/chat/completions"
                        : "https://openrouter.ai/api/v1/chat/completions")!
                },
                extraPayloadProvider: {
                    cleanup.provider == .openAI && cleanup.model.hasPrefix("gpt-5")
                        ? ["reasoning_effort": "none"] : [:]
                },
                customInstructionsProvider: { cleanup.customInstructions })
        }
        let coordinator = DictationCoordinator(
            recorder: recorder, engine: router, cleanup: cleanup,
            inserter: TextInserter(notifier: notifier),
            notifier: notifier, // Phase 2: cap + failure notifications
            history: history,
            frontmostApp: { activeApp.frontmost },
            dictionaryTermsProvider: { [history] in history?.dictionaryTermStrings() ?? [] },
            dictionaryPromptTermsProvider: { [history] in history?.dictionaryPromptTerms() ?? [] },
            snippetExpansionsProvider: { [history] in history?.snippetExpansions() ?? [] },
            pressEnterEnabledProvider: {
                defaults.object(forKey: "enablePressEnterAction") as? Bool ?? false
            },
            focusedContextProvider: {
                let target = activeApp.frontmost.bundleID
                let enabled = defaults.object(forKey: "contextAwarenessEnabled") as? Bool ?? false
                let excluded = defaults.stringArray(forKey: "contextExcludedBundleIDs") ?? []
                guard ContextPolicy.mayRead(enabled: enabled, bundleID: target,
                                            exclusions: excluded) else { return nil }
                return contextReader.read()
            },
            cleanupLevelProvider: {
                CleanupLevel(rawValue: defaults.string(forKey: "cleanupLevel") ?? "high") ?? .high
            },
            stylePresetProvider: { bundleID in resolver.resolve(bundleID: bundleID) },
            pinnedLanguageProvider: {
                // Settings stores the ISO code ("de"); the prompt wants a name ("German").
                defaults.string(forKey: "pinnedLanguage").flatMap {
                    Locale(identifier: "en").localizedString(forIdentifier: $0)
                }
            },
            cleanupModelProvider: {
                // Stamped into DictationRecord.cleanupModel (spec §8) — same key CleanupService reads.
                defaults.string(forKey: "cleanupModel") ?? "google/gemini-2.5-flash-lite"
            },
            keepRecordingsProvider: {
                defaults.object(forKey: "keepRecordings") as? Bool ?? false
            },
            instantSkipCleanupProvider: {
                defaults.object(forKey: "instantSkipCleanup") as? Bool ?? false
            },
            batchProgressEnabledProvider: {
                (defaults.string(forKey: "engineMode") ?? "cloud") == "cloud"
                    && (defaults.object(forKey: "streamBatchTranscription") as? Bool ?? true)
            },
            liveTypeProvider: {
                defaults.object(forKey: "instantLiveType") as? Bool ?? false
            },
            sessionConfigurationProvider: { target in
                sessionResolver.resolve(targetBundleID: target.bundleID)
            },
            transcriptionEngineProvider: configuredTranscriptionEngine,
            cleanupServiceProvider: configuredCleanupService,
            liveInserter: LiveTextInserter(),
            diagnosticSink: { event in
                Self.diagnosticsLogger.notice("\(event.rawValue, privacy: .public)")
            },
            configuredLiveSessionFactory: { configuration, onPartial in
                guard configuration.engineMode == .instant else {
                    throw EngineError.invalidResponse // coordinator treats factory throw as "no live session"
                }
                guard !configuration.transcription.speakerFilteringRequested else {
                    throw EngineError.invalidResponse // speaker labels are batch-only
                }
                let key = credential(.openAIKey) ?? ""
                guard !key.isEmpty else { throw EngineError.missingAPIKey }
                let context = TranscriptionContext.build(
                    prompt: configuration.transcription.contextPrompt,
                    dictionaryTerms: configuration.dictionaryPromptTerms,
                    languageCodes: configuration.transcription.expectedLanguageCodes)
                let session = OpenAIRealtimeSession(
                    transport: OpenAIRealtimeTransport(apiKey: key),
                    model: configuration.transcription.realtimeModel,
                    context: context,
                    delay: configuration.transcription.realtimeDelay,
                    encoder: RealtimePCMEncoder(),
                    onPartial: onPartial)
                try await session.begin()
                return session
            })

        self.setupState = setupState
        self.keychain = keychain
        self.settings = settings
        self.profiles = profiles
        self.fnMonitor = fnMonitor
        self.escMonitor = escMonitor
        self.recorder = recorder
        self.speakerReference = speakerReference
        self.activeApp = activeApp
        self.contextReader = contextReader
        self.shortcuts = shortcuts
        self.permissions = permissions
        self.notifier = notifier
        self.pasteLastInserter = pasteLastInserter
        self.coordinator = coordinator
        self.history = history
        self.modelDownloader = modelDownloader
        self.onboarding = onboarding
        self.selectionTransforms = selectionTransforms
        self.selectionTransformWindow = selectionTransformWindow
    }

    /// Automatically show setup only for a genuinely incomplete installation.
    /// Permission loss after completion is handled by targeted recovery UI.
    func showOnboardingIfNeeded() {
        let micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let axTrusted = AXIsProcessTrusted()
        guard SetupLaunchPolicy.shouldShowOnboarding(
            setupCompleted: setupState.setupCompleted,
            microphoneGranted: micGranted,
            accessibilityGranted: axTrusted
        ) else { return }
        showOnboarding()
    }

    /// Also reachable from Settings → General → "Run Setup Assistant…".
    func showOnboarding() {
        onboarding.show(keychain: keychain, settings: settings,
                        modelDownloader: modelDownloader, profiles: profiles,
                        setupState: setupState)
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
        // One-time: capture the user's current flat settings as a "My Settings"
        // profile (verbatim) and select it. No apply — settings are unchanged; this
        // just populates the profile picker so the selection matches live settings.
        profiles.migrateIfNeeded(from: settings)
        flowBar = FlowBarPanel(coordinator: coordinator, recorder: recorder,
                               settings: settings,
                               onHideForHour: { [weak self] in self?.hidePillTemporarily() },
                               onHidePermanently: { [weak self] in self?.settings.showFlowBar = false })
        // Route through the serial gesture queue so press/release/double-tap can't
        // interleave across their async handlers (the hands-free double-tap race).
        fnMonitor.onPress = { [coordinator] in coordinator.handleGesture(.press) }
        fnMonitor.onRelease = { [coordinator] in coordinator.handleGesture(.release) }
        fnMonitor.onDoubleTap = { [coordinator] in coordinator.handleGesture(.toggleHandsFree) }
        fnMonitor.start()
        escMonitor.onEsc = { [coordinator] in coordinator.cancel() }
        trackDictationActivity()
        shortcuts.enablePasteLast { [coordinator, pasteLastInserter] in
            guard let last = coordinator.lastResult?.cleanedText else { return }
            Task { try? await pasteLastInserter.insert(last) }
        }
        shortcuts.enableSelectionTransform { [contextReader, selectionTransforms,
                                               selectionTransformWindow, history, notifier] in
            guard let target = contextReader.captureSelectionTarget() else {
                notifier.notify(title: "Select text first",
                                body: "Highlight editable text, then press ⇧⌥T.")
                return
            }
            selectionTransforms.capture(target)
            selectionTransformWindow.show(coordinator: selectionTransforms, history: history)
        }
        trackPillVisibility()
        trackCustomShortcuts()
        trackDockIconPolicy()
        trackPillPosition()
        trackPillActivity()
        showOnboardingIfNeeded()
        checkPermissionHealthOnce()
    }

#if DEBUG
    func startE2E() {
        guard let configuration = environment.e2e,
              let reporter = try? E2EReporter(configuration: configuration) else { return }
        let activeApp = self.activeApp
        let runtime = E2ERuntime(reporter: reporter,
                                 targetBundleID: { activeApp.frontmost.bundleID },
                                 inserter: TextInserter(notifier: notifier),
                                 fixtureText: configuration.fixtureText)
        let bridge = E2ETestControlBridge(configuration: configuration, runtime: runtime)
        do {
            try bridge.start()
            e2eBridge = bridge
        } catch {
            assertionFailure("E2E bridge initialization failed")
        }
    }

    func stopE2E() {
        e2eBridge?.stop()
        e2eBridge = nil
    }

    func startScreenshotDemo() {
        screenshotDemoPill = ScreenshotDemoPillPanel()
        NSApp.activate(ignoringOtherApps: true)
    }
#endif

    private var permissionHealthChecked = false

    /// Recheck TCC health on every launch without opening or activating a window.
    /// Notifications only take the user to repair UI after an explicit click.
    private func checkPermissionHealthOnce() {
        guard setupState.setupCompleted, !permissionHealthChecked else { return }
        permissionHealthChecked = true
        permissions.refresh()
        for missing in permissions.health.missing {
            switch missing {
            case .microphone:
                notifier.notify(title: "Microphone access needed",
                                body: "Talkie cannot record until microphone access is restored.",
                                destination: .microphone)
            case .accessibility:
                notifier.notify(title: "Accessibility access needed",
                                body: "Dictation will be copied to the clipboard until access is restored.",
                                destination: .accessibility)
            case .engines:
                break
            }
        }
    }

    private var pillFlashTask: Task<Void, Never>?

    /// Re-arming observation loop: panel existence + mouse participation follow
    /// the dictation state and pill style (PillVisibilityPolicy). After a
    /// completion, keeps the panel up briefly so the neutral ring can exit.
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
        let completionDuration = PillMotionProfile.calmFlow.completionPanelDuration
        let recentlyCompleted = coordinator.lastCompletedAt
            .map { Date().timeIntervalSince($0) < completionDuration } ?? false
        flowBar?.applyActivity(state: coordinator.state, recentlyCompleted: recentlyCompleted)
        pillFlashTask?.cancel()
        if recentlyCompleted {
            // Re-evaluate once the completion ring exits so the panel orders out.
            pillFlashTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(completionDuration + 0.1))
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
                                 onPress: { [coordinator] in coordinator.handleGesture(.press) },
                                 onRelease: { [coordinator] in coordinator.handleGesture(.release) })
        shortcuts.bindHandsFree(settings.handsFreeShortcut.flatMap(ShortcutSpec.init(storage:)),
                                onToggle: { [coordinator] in coordinator.handleGesture(.toggleHandsFree) })
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
#if DEBUG
    private var e2eSettingsWindow: NSWindow?
#endif

    enum LaunchAction: Equatable {
        case startProductionUI
        case startE2E
        case startScreenshotDemo
        case terminate
    }

    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    static func launchAction(for mode: AppRuntimeMode) -> LaunchAction {
        switch mode {
        case .production:
            .startProductionUI
        case .e2e:
            .startE2E
        case .invalidE2E:
            .terminate
        case .screenshotDemo:
            .startScreenshotDemo
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self // harmless under tests
#if DEBUG
        if AppServices.shared.environment.e2e?.scenario == "settings-model-controls" {
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    self?.showE2ESettingsWindow()
                }
            }
        }
#endif
        guard !Self.isRunningTests else { return }
#if DEBUG
        switch Self.launchAction(for: AppServices.shared.environment.mode) {
        case .startE2E:
            AppServices.shared.startE2E()
            return
        case .startScreenshotDemo:
            AppServices.shared.startScreenshotDemo()
            return
        case .terminate:
            NSApp.terminate(nil)
            return
        case .startProductionUI:
            break
        }
#endif
        AppServices.shared.startUI()
    }

#if DEBUG
    @MainActor
    private func showE2ESettingsWindow() {
        let content = SettingsView(
            keychain: AppServices.shared.keychain,
            settings: AppServices.shared.settings)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false)
        window.title = "Talkie Settings"
        window.contentViewController = NSHostingController(rootView: content)
        window.isReleasedWhenClosed = false
        window.center()
        window.orderFrontRegardless()
        window.makeKey()
        NSApp.activate(ignoringOtherApps: true)
        e2eSettingsWindow = window
    }
#endif

    func applicationWillTerminate(_ notification: Notification) {
#if DEBUG
        AppServices.shared.stopE2E()
#endif
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let action = response.notification.request.content.userInfo["talkie.action"] as? String,
           let destination = NotificationDestination(action: action) {
            if let url = destination.systemSettingsURL {
                NSWorkspace.shared.open(url)
                completionHandler()
                return
            }
            NSApp.activate(ignoringOtherApps: true)
            // SwiftUI Settings has no public programmatic opener; this selector is the
            // established workaround on macOS 14 — verify it still resolves on the SDK you build with.
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        completionHandler()
    }
}
