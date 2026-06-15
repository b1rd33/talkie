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
    /// The Flow Bar pill's visual style (see PillStyle). Persisted as its raw value.
    var pillStyle: PillStyle { didSet { defaults.set(pillStyle.rawValue, forKey: "pillStyle") } }
    /// "bottomCenter" | "bottomLeft" | "bottomRight" | "topCenter"
    var pillPosition: String { didSet { defaults.set(pillPosition, forKey: "pillPosition") } }
    var keepRecordings: Bool { didSet { defaults.set(keepRecordings, forKey: "keepRecordings") } }
    /// Instant streaming inserts the raw streamed text with no cleanup LLM pass.
    var instantSkipCleanup: Bool { didSet { defaults.set(instantSkipCleanup, forKey: "instantSkipCleanup") } }
    /// Type the streamed text into the focused app live while speaking. Implies
    /// instantSkipCleanup — you can't re-polish text already typed into a document.
    var instantLiveType: Bool {
        didSet {
            defaults.set(instantLiveType, forKey: "instantLiveType")
            if instantLiveType { instantSkipCleanup = true }
        }
    }
    var cleanupLevel: String { didSet { defaults.set(cleanupLevel, forKey: "cleanupLevel") } }
    var customCleanupPrompt: String { didSet { defaults.set(customCleanupPrompt, forKey: "customCleanupPrompt") } }
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
        pillStyle = PillStyle(migrating: defaults.string(forKey: "pillStyle"))
        pillPosition = defaults.string(forKey: "pillPosition") ?? "bottomCenter"
        keepRecordings = defaults.object(forKey: "keepRecordings") as? Bool ?? false
        instantSkipCleanup = defaults.object(forKey: "instantSkipCleanup") as? Bool ?? false
        instantLiveType = defaults.object(forKey: "instantLiveType") as? Bool ?? false
        cleanupLevel = defaults.string(forKey: "cleanupLevel") ?? "high"
        customCleanupPrompt = defaults.string(forKey: "customCleanupPrompt") ?? ""
        pinnedLanguage = defaults.string(forKey: "pinnedLanguage")
        pttShortcut = defaults.string(forKey: "pttShortcut")
        handsFreeShortcut = defaults.string(forKey: "handsFreeShortcut")
        // Persist the migrated pill style so a retired raw value (classic/dot/
        // compact) is normalized on disk and never re-read.
        defaults.set(pillStyle.rawValue, forKey: "pillStyle")
    }
}
