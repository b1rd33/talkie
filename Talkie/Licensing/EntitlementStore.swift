import Foundation
import Observation

enum Entitlement: Equatable {
    case licensed
    case trial(daysLeft: Int)
    case expired
}

/// Why dictation is gated — becomes the pill's error message. A trial the
/// user never started is NOT "expired" (spec §9 deviation, see header notes).
enum EntitlementError: Error, LocalizedError, Equatable {
    case notStarted
    case expired

    var errorDescription: String? {
        switch self {
        case .notStarted: return "Start your free 14-day trial in Settings → License."
        case .expired: return "Trial expired — enter your license in Settings."
        }
    }
}

/// Single observable source of truth for "may this user dictate?" —
/// combines LicenseManager and TrialManager. The gate (`canDictate`/`gateError`)
/// answers LIVE from the sources; the displayed `current` is refreshed at launch
/// (init), on activation/trial start (explicit), on .licenseActivated, on every
/// gated key press (Task 8 wiring), and when licensing UI appears (.onAppear).
@MainActor
@Observable
final class EntitlementStore {
    private(set) var current: Entitlement = .expired

    private let license: LicenseManager
    private let trial: TrialManager

    init(license: LicenseManager, trial: TrialManager) {
        self.license = license
        self.trial = trial
        refresh()
        // Belt-and-braces: anything that activates a license elsewhere refreshes us.
        // refresh() only READS state — never calls checkLicense()/activateLicense(),
        // which post this notification (would loop).
        NotificationCenter.default.addObserver(
            forName: .licenseActivated, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// Live — computed from the sources, NOT the cached `current`, so a trial
    /// that expires (or a clock rolled back) while the app stays open gates
    /// the very next key press without waiting for a relaunch.
    var canDictate: Bool { license.isLicensed || trial.isActive }
    /// Live gate verdict for the coordinator: nil = may dictate.
    var gateError: EntitlementError? {
        if canDictate { return nil }
        return trial.hasStarted ? .expired : .notStarted
    }
    var trialHasStarted: Bool { trial.hasStarted }
    var machineID: String { license.machineID }
    var licenseExpirationText: String? { license.currentLicense?.expirationFormatted }

    func refresh() {
        if license.isLicensed {
            current = .licensed
        } else if trial.isActive {
            current = .trial(daysLeft: trial.daysRemaining)
        } else {
            current = .expired
        }
    }

    /// User clicked "Start 14-day trial" (onboarding). Never called automatically.
    func startTrial() {
        trial.startTrial()
        refresh()
    }

    func activate(_ keyString: String) -> LicenseValidationResult {
        let result = license.activateLicense(keyString: keyString)
        refresh()
        return result
    }
}
