import AppKit
import SwiftUI

/// Standard titled window hosting the onboarding flow. Unlike the Flow Bar,
/// this one MAY take focus — the user is interacting with it. Closable at any
/// step (onboarding re-opens on next launch while entitlement/permissions are missing,
/// and is re-runnable from Settings → General).
@MainActor
final class OnboardingWindow {
    private var window: NSWindow?

    func show(entitlements: EntitlementStore, keychain: KeychainStore,
              settings: SettingsStore, modelDownloader: ModelDownloader, profiles: ProfileStore) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = OnboardingView(entitlements: entitlements, keychain: keychain,
                                  settings: settings, modelDownloader: modelDownloader,
                                  profiles: profiles,
                                  onFinished: { [weak self] in self?.close() })
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Welcome to Talkie"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
        window = nil
    }
}
