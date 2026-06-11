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
    let coordinator: DictationCoordinator
    let history: HistoryStore?
    private(set) var flowBar: FlowBarPanel?

    private init() {
        let engine = OpenAIEngine(
            apiKeyProvider: { KeychainStore().read(.openAIKey) },
            modelProvider: { UserDefaults.standard.string(forKey: "transcriptionModel") ?? "gpt-4o-mini-transcribe" }
        )
        let cleanup = CleanupService(
            apiKeyProvider: { KeychainStore().read(.openRouterKey) },
            modelProvider: { UserDefaults.standard.string(forKey: "cleanupModel") ?? "google/gemini-2.5-flash" }
        )
        let history = try? HistoryStore()
        self.history = history
        let notifier = Notifier()
        coordinator = DictationCoordinator(
            recorder: recorder, engine: engine, cleanup: cleanup,
            inserter: TextInserter(notifier: notifier),
            notifier: notifier,
            history: history,
            frontmostApp: {
                let app = NSWorkspace.shared.frontmostApplication
                return (app?.bundleIdentifier, app?.localizedName)
            })
    }

    func startUI() {
        flowBar = FlowBarPanel(coordinator: coordinator, recorder: recorder)
        fnMonitor.onPress = { [coordinator] in Task { await coordinator.dictationKeyPressed() } }
        fnMonitor.onRelease = { [coordinator] in Task { await coordinator.dictationKeyReleased() } }
        fnMonitor.onDoubleTap = { [coordinator] in Task { await coordinator.handsFreeToggled() } }
        fnMonitor.start()
        escMonitor.onEsc = { [coordinator] in coordinator.cancel() }
        trackDictationActivity()
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
