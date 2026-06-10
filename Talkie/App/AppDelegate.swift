import AppKit
import Foundation

/// Process-wide service container. Extended in later tasks.
@MainActor
final class AppServices {
    static let shared = AppServices()
    let keychain = KeychainStore()
    let settings = SettingsStore()
    let fnMonitor = FnKeyMonitor()
    private init() {}
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }
        AppServices.shared.fnMonitor.onPress = { NSLog("Talkie: fn DOWN") }
        AppServices.shared.fnMonitor.onRelease = { NSLog("Talkie: fn UP") }
        AppServices.shared.fnMonitor.start()
    }
}
