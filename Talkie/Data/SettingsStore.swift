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
    /// "openrouter" | "openai" — which API the cleanup chat call goes to.
    var cleanupProvider: String { didSet { defaults.set(cleanupProvider, forKey: "cleanupProvider") } }
    /// "openai" | "openrouter" — which API cloud (batch) transcription goes to.
    var transcriptionProvider: String { didSet { defaults.set(transcriptionProvider, forKey: "transcriptionProvider") } }
    var openrouterTranscriptionModel: String { didSet { defaults.set(openrouterTranscriptionModel, forKey: "openrouterTranscriptionModel") } }
    var showFlowBar: Bool { didSet { defaults.set(showFlowBar, forKey: "showFlowBar") } }
    var launchAtLogin: Bool { didSet { defaults.set(launchAtLogin, forKey: "launchAtLogin") } }
    var engineMode: String { didSet { defaults.set(engineMode, forKey: "engineMode") } }
    var showDockIcon: Bool { didSet { defaults.set(showDockIcon, forKey: "showDockIcon") } }
    /// "classic" (notch when idle) | "dot" (small dot) | "hidden" (invisible until active)
    /// | "compact" (hidden idle + smaller active pill).
    var pillStyle: String { didSet { defaults.set(pillStyle, forKey: "pillStyle") } }
    /// "bottomCenter" | "bottomLeft" | "bottomRight" | "topCenter"
    var pillPosition: String { didSet { defaults.set(pillPosition, forKey: "pillPosition") } }
    var keepRecordings: Bool { didSet { defaults.set(keepRecordings, forKey: "keepRecordings") } }
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
        cleanupModel = defaults.string(forKey: "cleanupModel") ?? "google/gemini-2.5-flash-lite"
        cleanupProvider = defaults.string(forKey: "cleanupProvider") ?? "openrouter"
        transcriptionProvider = defaults.string(forKey: "transcriptionProvider") ?? "openai"
        openrouterTranscriptionModel = defaults.string(forKey: "openrouterTranscriptionModel") ?? "mistralai/voxtral-mini-transcribe"
        showFlowBar = defaults.object(forKey: "showFlowBar") as? Bool ?? true
        launchAtLogin = defaults.object(forKey: "launchAtLogin") as? Bool ?? false
        engineMode = defaults.string(forKey: "engineMode") ?? "cloud"
        showDockIcon = defaults.object(forKey: "showDockIcon") as? Bool ?? false
        pillStyle = defaults.string(forKey: "pillStyle") ?? "classic"
        pillPosition = defaults.string(forKey: "pillPosition") ?? "bottomCenter"
        keepRecordings = defaults.object(forKey: "keepRecordings") as? Bool ?? false
        cleanupLevel = defaults.string(forKey: "cleanupLevel") ?? "high"
        pinnedLanguage = defaults.string(forKey: "pinnedLanguage")
        pttShortcut = defaults.string(forKey: "pttShortcut")
        handsFreeShortcut = defaults.string(forKey: "handsFreeShortcut")
    }
}
