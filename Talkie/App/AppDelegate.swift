import AppKit
import Foundation

@MainActor
final class AppServices {
    static let shared = AppServices()

    let keychain = KeychainStore()
    let settings = SettingsStore()
    let fnMonitor = FnKeyMonitor()
    let recorder = AudioRecorder()
    let coordinator: DictationCoordinator
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
        coordinator = DictationCoordinator(recorder: recorder, engine: engine,
                                           cleanup: cleanup, inserter: TextInserter())
    }

    func startUI() {
        flowBar = FlowBarPanel(coordinator: coordinator, recorder: recorder)
        fnMonitor.onPress = { [coordinator] in Task { await coordinator.dictationKeyPressed() } }
        fnMonitor.onRelease = { [coordinator] in Task { await coordinator.dictationKeyReleased() } }
        fnMonitor.start()
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
