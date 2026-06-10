import AppKit
import Foundation

/// Process-wide service container. Extended in later tasks.
@MainActor
final class AppServices {
    static let shared = AppServices()
    let keychain = KeychainStore()
    let settings = SettingsStore()
    private init() {}
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }
        // Components are wired here in later tasks.
    }
}
