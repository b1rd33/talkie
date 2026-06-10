import Foundation
import Observation

/// Non-secret settings. Secrets belong in KeychainStore.
@Observable
final class SettingsStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var transcriptionModel: String {
        get { defaults.string(forKey: "transcriptionModel") ?? "gpt-4o-mini-transcribe" }
        set { defaults.set(newValue, forKey: "transcriptionModel") }
    }

    var cleanupModel: String {
        get { defaults.string(forKey: "cleanupModel") ?? "google/gemini-2.5-flash" }
        set { defaults.set(newValue, forKey: "cleanupModel") }
    }
}
