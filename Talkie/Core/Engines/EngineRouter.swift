import Foundation

/// Policy layer over the two engines (spec §10 row 1):
/// - mode "cloud": cloud first; on connectivity loss or a server-side (5xx) failure,
///   fall back to local if available. 4xx does NOT fall back — a 401/403 must surface
///   as the invalid-key error (spec §10 row 3) instead of being masked by local.
/// - mode "local": local only. Missing models fail closed and never contact cloud.
struct EngineRouter: TranscriptionEngine {
    let cloud: TranscriptionEngine
    let local: TranscriptionEngine
    var mode: @Sendable () -> String          // "cloud" | "local"
    var localAvailable: @Sendable () -> Bool  // models downloaded?

    init(
        cloud: TranscriptionEngine,
        local: TranscriptionEngine,
        mode: @escaping @Sendable () -> String,
        localAvailable: @escaping @Sendable () -> Bool
    ) {
        self.cloud = cloud
        self.local = local
        self.mode = mode
        self.localAvailable = localAvailable
    }

    init(
        cloud: TranscriptionEngine,
        local: TranscriptionEngine,
        configuration: DictationSessionConfiguration,
        localAvailable: @escaping @Sendable () -> Bool
    ) {
        self.cloud = cloud
        self.local = local
        let resolvedMode = configuration.permitsCloudTranscription
            ? configuration.engineMode.rawValue
            : EngineMode.local.rawValue
        self.mode = { resolvedMode }
        self.localAvailable = localAvailable
    }

    func transcribe(
        _ audio: RecordedAudio,
        dictionaryTerms: [String],
        onPartial: TranscriptionProgressSink?
    ) async throws -> Transcript {
        if mode() == "local" {
            guard localAvailable() else { throw EngineError.localModelsUnavailable }
            return try await local.transcribe(
                audio, dictionaryTerms: dictionaryTerms, onPartial: onPartial)
        }
        do {
            return try await cloud.transcribe(
                audio, dictionaryTerms: dictionaryTerms, onPartial: onPartial)
        } catch let error as EngineError where Self.triggersFallback(error) && localAvailable() {
            var transcript = try await local.transcribe(
                audio, dictionaryTerms: dictionaryTerms, onPartial: onPartial)
            transcript.usedFallback = true
            return transcript
        }
    }

    /// Spec §10 row 1: connectivity loss and server-side (5xx) failures trigger fallback.
    private static func triggersFallback(_ error: EngineError) -> Bool {
        switch error {
        case .offline: return true
        case .requestFailed(let status, _): return status >= 500
        default: return false
        }
    }
}
