import Foundation
import Observation

/// Which API key(s) the user has — drives first-run profile auto-selection.
enum KeyChoice { case openAI, openRouter, neither }

/// Holds the user's custom profiles and which profile is selected. Built-ins are
/// code constants (`DictationProfile.builtIns`); only custom profiles + the selected
/// id are persisted (as JSON in UserDefaults, same didSet pattern as SettingsStore).
@Observable
final class ProfileStore {
    @ObservationIgnored private let defaults: UserDefaults

    var customProfiles: [DictationProfile] { didSet { persistCustom() } }
    var selectedProfileID: UUID? { didSet { persistSelected() } }

    /// Built-ins first, then the user's custom profiles.
    var allProfiles: [DictationProfile] { DictationProfile.builtIns + customProfiles }
    var selectedProfile: DictationProfile? { allProfiles.first { $0.id == selectedProfileID } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.customKey),
           let decoded = try? JSONDecoder().decode([DictationProfile].self, from: data) {
            customProfiles = decoded
        } else {
            customProfiles = []
        }
        if let raw = defaults.string(forKey: Self.selectedKey), let id = UUID(uuidString: raw) {
            selectedProfileID = id
        } else {
            selectedProfileID = nil
        }
    }

    func add(_ profile: DictationProfile) { customProfiles.append(profile) }
    func select(_ id: UUID) { selectedProfileID = id }

    /// Removes a custom profile; if it was selected, falls back to Private/Offline.
    /// Built-ins can't be deleted.
    func delete(_ id: UUID) {
        customProfiles.removeAll { $0.id == id }
        if selectedProfileID == id { selectedProfileID = DictationProfile.privateOffline.id }
    }

    /// One-time migration of an existing install: when nothing is selected yet, map the
    /// current flat settings onto a built-in by SHAPE (not exact models), or wrap them
    /// verbatim in a custom "My Settings" profile, and select it. No-op once selected.
    func migrateIfNeeded(from settings: SettingsStore) {
        guard selectedProfileID == nil else { return }
        let snapshot = DictationProfile(snapshot: settings)
        if let match = DictationProfile.builtIns.first(where: { snapshot.shapeMatches($0) }) {
            selectedProfileID = match.id
        } else {
            customProfiles.append(snapshot)
            selectedProfileID = snapshot.id
        }
    }

    /// First-run auto-selection from the "which key do you have?" answer.
    static func firstRunProfile(forKeyChoice choice: KeyChoice) -> DictationProfile {
        switch choice {
        case .openAI: return .instant
        case .openRouter: return .cheapestCloud
        case .neither: return .privateOffline
        }
    }

    // MARK: persistence

    private static let customKey = "customProfiles"
    private static let selectedKey = "selectedProfileID"

    private func persistCustom() {
        if let data = try? JSONEncoder().encode(customProfiles) {
            defaults.set(data, forKey: Self.customKey)
        }
    }
    private func persistSelected() {
        if let id = selectedProfileID { defaults.set(id.uuidString, forKey: Self.selectedKey) }
        else { defaults.removeObject(forKey: Self.selectedKey) }
    }
}
