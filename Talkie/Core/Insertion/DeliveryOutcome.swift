import Foundation

/// The mechanism Talkie used to make a completed transcript available.
///
/// A route describes what was attempted; it does not by itself claim that the
/// destination accepted the text. `DeliveryVerification` carries that fact.
enum DeliveryRoute: String, Codable, Equatable, Sendable {
    case accessibilityRange
    case liveUnicodeEvents
    case clipboardPaste
    case clipboardOnly
    case refused
}

enum DeliveryVerification: String, Codable, Equatable, Sendable {
    case verified
    case unverified
    case failed
}

/// Privacy-safe result of a delivery attempt. It deliberately contains no
/// transcript or clipboard contents, so it can be persisted and diagnosed.
struct DeliveryOutcome: Equatable, Sendable {
    let route: DeliveryRoute
    let verification: DeliveryVerification
    let targetBundleID: String?
    let fallbackReason: String?
    let revisionCount: Int

    /// True only when Talkie actually attempted to modify the press-time target.
    /// Clipboard-only recovery and refused/failed routes must never arm follow-up
    /// Return or Undo actions.
    var attemptedTargetInsertion: Bool {
        guard verification != .failed else { return false }
        switch route {
        case .accessibilityRange, .liveUnicodeEvents, .clipboardPaste:
            return true
        case .clipboardOnly, .refused:
            return false
        }
    }

    init(
        route: DeliveryRoute,
        verification: DeliveryVerification,
        targetBundleID: String? = nil,
        fallbackReason: String? = nil,
        revisionCount: Int = 0
    ) {
        self.route = route
        self.verification = verification
        self.targetBundleID = targetBundleID
        self.fallbackReason = fallbackReason
        self.revisionCount = revisionCount
    }
}
