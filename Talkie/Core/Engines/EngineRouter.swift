import Foundation

/// Policy layer over the two engines (spec §10 row 1):
/// - mode "cloud": cloud first; on connectivity loss or a server-side (5xx) failure,
///   fall back to local if available. 4xx does NOT fall back — a 401/403 must surface
///   as the invalid-key error (spec §10 row 3) instead of being masked by local.
/// - mode "local": local if models are present, else cloud (never strand the user).
struct EngineRouter: TranscriptionEngine {
    let cloud: TranscriptionEngine
    let local: TranscriptionEngine
    var mode: @Sendable () -> String          // "cloud" | "local"
    var localAvailable: @Sendable () -> Bool  // models downloaded?

    func transcribe(_ audio: RecordedAudio, dictionaryTerms: [String]) async throws -> Transcript {
        if mode() == "local", localAvailable() {
            return try await local.transcribe(audio, dictionaryTerms: dictionaryTerms)
        }
        do {
            return try await cloud.transcribe(audio, dictionaryTerms: dictionaryTerms)
        } catch let error as EngineError where Self.triggersFallback(error) && localAvailable() {
            var transcript = try await local.transcribe(audio, dictionaryTerms: dictionaryTerms)
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
