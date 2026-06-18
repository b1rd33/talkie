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

    /// Creates a new custom profile from the current settings, selects it, returns it.
    @discardableResult
    func saveAsNewProfile(named name: String, from settings: SettingsStore) -> DictationProfile {
        var profile = DictationProfile(snapshot: settings)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.name = uniqueCustomName(trimmed.isEmpty ? "My Settings" : trimmed)
        customProfiles.append(profile)
        selectedProfileID = profile.id
        return profile
    }

    /// Appends " 2", " 3", … if a custom profile already uses `base`, so the picker
    /// never shows two indistinguishable rows.
    private func uniqueCustomName(_ base: String) -> String {
        let existing = Set(customProfiles.map(\.name))
        guard existing.contains(base) else { return base }
        var n = 2
        while existing.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    /// Saves the current settings into the selected CUSTOM profile (keeps its id/name).
    /// No-op for built-ins (immutable) or when nothing is selected.
    func saveCurrentSettingsToSelected(from settings: SettingsStore) {
        guard let id = selectedProfileID,
              let idx = customProfiles.firstIndex(where: { $0.id == id }) else { return }
        var updated = DictationProfile(snapshot: settings)
        updated.id = customProfiles[idx].id
        updated.name = customProfiles[idx].name
        updated.builtIn = false
        customProfiles[idx] = updated
    }

    /// Removes a custom profile; if it was selected, falls back to Private/Offline.
    /// Built-ins can't be deleted.
    func delete(_ id: UUID) {
        customProfiles.removeAll { $0.id == id }
        if selectedProfileID == id { selectedProfileID = DictationProfile.privateOffline.id }
    }

    /// One-time migration of an existing install: when nothing is selected yet, wrap the
    /// current flat settings VERBATIM in a custom "My Settings" profile and select it.
    /// Verbatim (not snap-to-built-in) so migration never silently changes a user's tuned
    /// config, and the selected profile always matches the live settings. No-op once
    /// selected. (`shapeMatches` stays available for a future "your settings resemble
    /// built-in X — switch?" hint in Dev mode.)
    func migrateIfNeeded(from settings: SettingsStore) {
        // Re-migrate when there's no VALID selection — covers first run AND a stale id
        // (e.g. custom-profile JSON that failed to decode), so the picker never points
        // at a non-existent profile.
        guard selectedProfile == nil else { return }
        let snapshot = DictationProfile(snapshot: settings)
        customProfiles.append(snapshot)
        selectedProfileID = snapshot.id
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
