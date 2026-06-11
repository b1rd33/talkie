import AppKit
import Foundation

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
    private(set) var flowBar: FlowBarPanel?

    private init() {
        let engine = OpenAIEngine(
            apiKeyProvider: { KeychainStore().read(.openAIKey) },
            modelProvider: { UserDefaults.standard.string(forKey: "transcriptionModel") ?? "gpt-4o-mini-transcribe" },
            languageProvider: { UserDefaults.standard.string(forKey: "pinnedLanguage") }
        )
        let cleanup = CleanupService(
            apiKeyProvider: { KeychainStore().read(.openRouterKey) },
            modelProvider: { UserDefaults.standard.string(forKey: "cleanupModel") ?? "google/gemini-2.5-flash" }
        )
        let backend = FluidAudioBackend()
        let localEngine = ParakeetEngine(backend: backend)
        let router = EngineRouter(
            cloud: engine, local: localEngine,
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
                UserDefaults.standard.string(forKey: "cleanupModel") ?? "google/gemini-2.5-flash"
            })
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
        flowBar = FlowBarPanel(coordinator: coordinator, recorder: recorder,
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
    private func trackPillVisibility() {
        let visible = withObservationTracking {
            settings.showFlowBar
        } onChange: { [weak self] in
            Task { @MainActor in self?.trackPillVisibility() }
        }
        flowBar?.setVisible(visible)
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

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }
        AppServices.shared.startUI()
    }
}
