import Foundation
import Sparkle

/// Owns Sparkle's standard updater. Constructed exactly once, from
/// AppServices.startUI() — never under tests: startingUpdater: true begins the
/// scheduled-check cycle (Sparkle asks the user for permission before the
/// first automatic check) and reads SUFeedURL/SUPublicEDKey from Info.plist.
@MainActor
final class UpdaterService {
    private let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: nil)
    }

    /// Menu-bar action. Sparkle shows its own UI (progress, errors, up-to-date)
    /// and activates the app even though Talkie is LSUIElement.
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
