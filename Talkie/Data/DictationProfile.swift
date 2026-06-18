import Foundation

/// The API key(s) a profile needs to function, computed from its pipeline. Lets
/// Simple mode show only the field(s) that matter and reject impossible combos.
enum RequiredKey: Equatable {
    case none, openAI, openRouter, both
}

/// A named, self-consistent bundle of pipeline settings (engine + providers +
/// models + cleanup). Pinning these together prevents the invalid states users hit
/// with the flat settings (e.g. OpenAI provider + an OpenRouter-prefixed model, or
/// `Light` cleanup when they wanted reshaping).
///
/// Excludes: secrets (Keychain), `pinnedLanguage`, per-app styles, and ergonomics —
/// those stay independent of the chosen profile.
struct DictationProfile: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var builtIn: Bool

    var engineMode: String              // "cloud" | "instant" | "local"
    var instantSkipCleanup: Bool
    var instantLiveType: Bool
    var transcriptionProvider: String   // "openai" | "openrouter"
    var transcriptionModel: String
    var openrouterTranscriptionModel: String
    var cleanupLevel: String            // "none" | "light" | "medium" | "high" | "custom"
    var cleanupProvider: String         // "openai" | "openrouter"
    var cleanupModel: String
    var customCleanupPrompt: String

    /// Whether the cleanup LLM actually runs for this profile. Mirrors
    /// `DictationCoordinator.process()`: instant + skip-cleanup collapses to no cleanup.
    var cleanupRuns: Bool {
        cleanupLevel != "none" && !(engineMode == "instant" && instantSkipCleanup)
    }

    /// The key(s) this profile needs: union of the transcription provider's key and
    /// (when cleanup runs) the cleanup provider's key. Local + no cleanup needs none.
    var requiredKey: RequiredKey {
        var openAI = false
        var openRouter = false
        switch engineMode {
        case "local": break                         // on-device — no key
        case "instant": openAI = true               // realtime transcription is OpenAI
        default:                                     // "cloud" batch
            if transcriptionProvider == "openrouter" { openRouter = true } else { openAI = true }
        }
        if cleanupRuns {
            if cleanupProvider == "openrouter" { openRouter = true } else { openAI = true }
        }
        switch (openAI, openRouter) {
        case (true, true): return .both
        case (true, false): return .openAI
        case (false, true): return .openRouter
        case (false, false): return .none
        }
    }

    /// Writes the profile's pipeline fields onto the store. SettingsStore's didSets
    /// persist them, so every existing consumer (which reads UserDefaults) needs no
    /// rewiring. `instantLiveType` is written LAST because its didSet force-sets
    /// `instantSkipCleanup`; writing it last preserves the intended skip value for
    /// non-live-type profiles.
    func apply(to s: SettingsStore) {
        s.engineMode = engineMode
        s.transcriptionProvider = transcriptionProvider
        s.transcriptionModel = transcriptionModel
        s.openrouterTranscriptionModel = openrouterTranscriptionModel
        s.cleanupLevel = cleanupLevel
        s.cleanupProvider = cleanupProvider
        s.cleanupModel = cleanupModel
        s.customCleanupPrompt = customCleanupPrompt
        s.instantSkipCleanup = instantSkipCleanup
        s.instantLiveType = instantLiveType // LAST — its didSet force-sets instantSkipCleanup
    }
}

// MARK: - Built-in profiles

extension DictationProfile {
    /// Stable IDs so a selected built-in survives relaunch / JSON round-trips.
    static let privateOffline = DictationProfile(
        id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!,
        name: "Private / Offline", builtIn: true,
        engineMode: "local", instantSkipCleanup: false, instantLiveType: false,
        transcriptionProvider: "openai", transcriptionModel: ModelPresets.transcription[0],
        openrouterTranscriptionModel: ModelPresets.openrouterTranscription[0],
        cleanupLevel: "none", cleanupProvider: "openai", cleanupModel: ModelPresets.openaiCleanup[0],
        customCleanupPrompt: "")

    static let liveTyping = DictationProfile(
        id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!,
        name: "Live Typing", builtIn: true,
        engineMode: "instant", instantSkipCleanup: true, instantLiveType: true,
        transcriptionProvider: "openai", transcriptionModel: ModelPresets.transcription[0],
        openrouterTranscriptionModel: ModelPresets.openrouterTranscription[0],
        cleanupLevel: "none", cleanupProvider: "openai", cleanupModel: ModelPresets.openaiCleanup[0],
        customCleanupPrompt: "")

    static let instant = DictationProfile(
        id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A3")!,
        name: "Instant", builtIn: true,
        engineMode: "instant", instantSkipCleanup: false, instantLiveType: false,
        transcriptionProvider: "openai", transcriptionModel: ModelPresets.transcription[0],
        openrouterTranscriptionModel: ModelPresets.openrouterTranscription[0],
        cleanupLevel: "medium", cleanupProvider: "openai", cleanupModel: ModelPresets.openaiCleanup[0],
        customCleanupPrompt: "")

    static let bestAccuracy = DictationProfile(
        id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A4")!,
        name: "Best Accuracy", builtIn: true,
        engineMode: "cloud", instantSkipCleanup: false, instantLiveType: false,
        transcriptionProvider: "openai", transcriptionModel: ModelPresets.transcription[1],
        openrouterTranscriptionModel: ModelPresets.openrouterTranscription[0],
        cleanupLevel: "high", cleanupProvider: "openai", cleanupModel: ModelPresets.openaiCleanup[1],
        customCleanupPrompt: "")

    static let cheapestCloud = DictationProfile(
        id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A5")!,
        name: "Cheapest Cloud", builtIn: true,
        engineMode: "cloud", instantSkipCleanup: false, instantLiveType: false,
        transcriptionProvider: "openrouter", transcriptionModel: ModelPresets.transcription[0],
        openrouterTranscriptionModel: ModelPresets.openrouterTranscription[0],
        cleanupLevel: "medium", cleanupProvider: "openrouter", cleanupModel: ModelPresets.openrouterCleanup[0],
        customCleanupPrompt: "")

    /// First-run default is Private/Offline (no key required).
    static let builtIns: [DictationProfile] = [privateOffline, liveTyping, instant, bestAccuracy, cheapestCloud]
}
