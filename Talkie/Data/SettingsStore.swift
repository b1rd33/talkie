import Foundation
import Observation

/// Non-secret settings. Secrets belong in KeychainStore.
/// Stored properties with didSet persistence — @Observable does not track
/// computed properties for out-of-view observers (withObservationTracking).
@Observable
final class SettingsStore {
    @ObservationIgnored private let defaults: UserDefaults

    var transcriptionModel: String { didSet { defaults.set(transcriptionModel, forKey: "transcriptionModel") } }
    var cleanupModel: String { didSet { defaults.set(cleanupModel, forKey: "cleanupModel") } }
    var showFlowBar: Bool { didSet { defaults.set(showFlowBar, forKey: "showFlowBar") } }
    var launchAtLogin: Bool { didSet { defaults.set(launchAtLogin, forKey: "launchAtLogin") } }
    var engineMode: String { didSet { defaults.set(engineMode, forKey: "engineMode") } }
    var cleanupLevel: String { didSet { defaults.set(cleanupLevel, forKey: "cleanupLevel") } }
    var pttShortcut: String? {
        didSet {
            if let pttShortcut { defaults.set(pttShortcut, forKey: "pttShortcut") }
            else { defaults.removeObject(forKey: "pttShortcut") }
        }
    }
    var handsFreeShortcut: String? {
        didSet {
            if let handsFreeShortcut { defaults.set(handsFreeShortcut, forKey: "handsFreeShortcut") }
            else { defaults.removeObject(forKey: "handsFreeShortcut") }
        }
    }
    var pinnedLanguage: String? {
        didSet {
            if let pinnedLanguage { defaults.set(pinnedLanguage, forKey: "pinnedLanguage") }
            else { defaults.removeObject(forKey: "pinnedLanguage") }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        transcriptionModel = defaults.string(forKey: "transcriptionModel") ?? "gpt-4o-mini-transcribe"
        cleanupModel = defaults.string(forKey: "cleanupModel") ?? "google/gemini-2.5-flash"
        showFlowBar = defaults.object(forKey: "showFlowBar") as? Bool ?? true
        launchAtLogin = defaults.object(forKey: "launchAtLogin") as? Bool ?? false
        engineMode = defaults.string(forKey: "engineMode") ?? "cloud"
        cleanupLevel = defaults.string(forKey: "cleanupLevel") ?? "high"
        pinnedLanguage = defaults.string(forKey: "pinnedLanguage")
        pttShortcut = defaults.string(forKey: "pttShortcut")
        handsFreeShortcut = defaults.string(forKey: "handsFreeShortcut")
    }
}
