import Foundation

enum EngineMode: String, Sendable, Equatable {
    case cloud
    case instant
    case local

    init(storedValue: String) {
        self = EngineMode(rawValue: storedValue) ?? .cloud
    }
}

enum TranscriptionProvider: String, Sendable, Equatable {
    case openAI = "openai"
    case openRouter = "openrouter"

    init(storedValue: String) {
        self = TranscriptionProvider(rawValue: storedValue) ?? .openAI
    }
}

enum CleanupProvider: String, Sendable, Equatable {
    case openAI = "openai"
    case openRouter = "openrouter"

    init(storedValue: String) {
        self = CleanupProvider(rawValue: storedValue) ?? .openRouter
    }
}

enum DictationPrivacyClass: Sendable, Equatable {
    case localOnly
    case cloudTranscription
    case cloudCleanup
    case cloudTranscriptionAndCleanup
}

struct TranscriptionConfiguration: Sendable, Equatable {
    let provider: TranscriptionProvider
    let openAIModel: String
    let openRouterModel: String
    let realtimeModel: String
    let realtimeDelay: RealtimeTranscriptionDelay
    let contextPrompt: String
    let expectedLanguageCodes: [String]
    let streamBatch: Bool
    let speakerFilteringRequested: Bool
    let speakerFilter: SpeakerFilterConfiguration?

    var speakerFilteringEnabled: Bool { speakerFilteringRequested }
}

struct CleanupConfiguration: Sendable, Equatable {
    let level: CleanupLevel
    let provider: CleanupProvider
    let model: String
    let customInstructions: String

    var runs: Bool { level != .none }
}

/// An immutable description of one dictation. It is resolved exactly once, before
/// recorder startup, so settings/profile changes made while the key is held can
/// only affect the next dictation.
struct DictationSessionConfiguration: Sendable, Equatable {
    let profileID: UUID?
    let engineMode: EngineMode
    let transcription: TranscriptionConfiguration
    let cleanup: CleanupConfiguration
    let dictionaryTerms: [String]
    let dictionaryPromptTerms: [String]
    let snippets: [SnippetExpansion]
    let pressEnterEnabled: Bool
    let focusedContext: FocusedContext?
    let style: StylePreset
    let pinnedLanguage: String?
    let keepRecording: Bool
    let instantSkipCleanup: Bool
    let batchProgressEnabled: Bool
    let liveTypingEnabled: Bool

    var privacyClass: DictationPrivacyClass {
        let cloudTranscription = engineMode != .local
        let cloudCleanup = cleanup.runs
        switch (cloudTranscription, cloudCleanup) {
        case (false, false): return .localOnly
        case (true, false): return .cloudTranscription
        case (false, true): return .cloudCleanup
        case (true, true): return .cloudTranscriptionAndCleanup
        }
    }

    /// Defense in depth for the private profile: a local-only snapshot can never
    /// be routed to a cloud engine or cleanup service by a later fallback decision.
    var permitsCloudTranscription: Bool { engineMode != .local }
    var permitsCloudCleanup: Bool { cleanup.runs }
}

@MainActor
struct DictationSessionConfigurationResolver {
    let settings: SettingsStore
    var profileID: () -> UUID? = { nil }
    var dictionaryTerms: () -> [String] = { [] }
    var dictionaryPromptTerms: () -> [String] = { [] }
    var snippets: () -> [SnippetExpansion] = { [] }
    var focusedContext: (String?) -> FocusedContext? = { _ in nil }
    var style: (String?) -> StylePreset = { _ in .neutral }
    var speakerFilter: () -> SpeakerFilterConfiguration? = { nil }

    func resolve(targetBundleID: String?) -> DictationSessionConfiguration {
        let mode = settings.speakerFilteringEnabled
            ? EngineMode.cloud
            : EngineMode(storedValue: settings.engineMode)
        let provider = settings.speakerFilteringEnabled
            ? TranscriptionProvider.openAI
            : TranscriptionProvider(storedValue: settings.transcriptionProvider)
        let level = CleanupLevel(rawValue: settings.cleanupLevel) ?? .high
        let cleanup = CleanupConfiguration(
            level: level,
            provider: CleanupProvider(storedValue: settings.cleanupProvider),
            model: settings.cleanupModel,
            customInstructions: settings.customCleanupPrompt)
        let filter = settings.speakerFilteringEnabled ? speakerFilter() : nil

        return DictationSessionConfiguration(
            profileID: profileID(),
            engineMode: mode,
            transcription: TranscriptionConfiguration(
                provider: provider,
                openAIModel: settings.transcriptionModel,
                openRouterModel: settings.openrouterTranscriptionModel,
                realtimeModel: settings.realtimeTranscriptionModel,
                realtimeDelay: settings.realtimeTranscriptionDelay,
                contextPrompt: settings.transcriptionContextPrompt,
                expectedLanguageCodes: settings.expectedInputLanguages,
                streamBatch: settings.streamBatchTranscription,
                speakerFilteringRequested: settings.speakerFilteringEnabled,
                speakerFilter: filter),
            cleanup: cleanup,
            dictionaryTerms: dictionaryTerms(),
            dictionaryPromptTerms: dictionaryPromptTerms(),
            snippets: snippets(),
            pressEnterEnabled: settings.enablePressEnterAction,
            focusedContext: focusedContext(targetBundleID),
            style: style(targetBundleID),
            pinnedLanguage: settings.pinnedLanguage.flatMap {
                Locale(identifier: "en").localizedString(forIdentifier: $0)
            },
            keepRecording: settings.keepRecordings,
            instantSkipCleanup: settings.instantSkipCleanup,
            batchProgressEnabled: mode == .cloud && settings.streamBatchTranscription,
            liveTypingEnabled: settings.instantLiveType)
    }
}
