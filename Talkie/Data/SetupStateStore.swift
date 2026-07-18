import Foundation

/// Persists whether the user deliberately finished the setup assistant.
///
/// This store must be created before stores that write default values during
/// initialization. That lets an existing configured installation be migrated
/// without mistaking newly-written defaults for genuine legacy evidence.
@MainActor
final class SetupStateStore {
    static let completedKey = "setupCompleted"
    static let stateVersionKey = "setupStateVersion"
    static let currentStateVersion = 1

    private static let legacyConfigurationKeys: Set<String> = [
        "selectedProfileID",
        "customProfiles",
        "engineMode",
        "cleanupLevel",
        "pillStyle",
        "showFlowBar",
        "pttShortcut",
        "handsFreeShortcut",
    ]

    private let defaults: UserDefaults
    private(set) var setupCompleted: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if defaults.object(forKey: Self.completedKey) != nil {
            setupCompleted = defaults.bool(forKey: Self.completedKey)
        } else {
            let existingKeys = Set(defaults.dictionaryRepresentation().keys)
            setupCompleted = !existingKeys.isDisjoint(with: Self.legacyConfigurationKeys)
            defaults.set(setupCompleted, forKey: Self.completedKey)
        }

        defaults.set(Self.currentStateVersion, forKey: Self.stateVersionKey)
    }

    func markCompleted() {
        setupCompleted = true
        defaults.set(true, forKey: Self.completedKey)
        defaults.set(Self.currentStateVersion, forKey: Self.stateVersionKey)
    }
}

enum SetupLaunchPolicy {
    /// Permissions are deliberately not part of launch eligibility. Once setup
    /// is complete, revoked permissions use targeted recovery instead of taking
    /// focus by reopening the assistant.
    static func shouldShowOnboarding(setupCompleted: Bool,
                                     microphoneGranted _: Bool,
                                     accessibilityGranted _: Bool) -> Bool {
        !setupCompleted
    }
}
