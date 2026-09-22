import Foundation

/// Rejects persisted offline settings before any audio can reach a provider.
struct EngineRouter: TranscriptionEngine {
    let cloud: TranscriptionEngine
    var mode: @Sendable () -> String

    init(cloud: TranscriptionEngine, mode: @escaping @Sendable () -> String) {
        self.cloud = cloud
        self.mode = mode
    }

    init(cloud: TranscriptionEngine, configuration: DictationSessionConfiguration) {
        self.cloud = cloud
        self.mode = { configuration.engineMode.rawValue }
    }

    func transcribe(
        _ audio: RecordedAudio,
        dictionaryTerms: [String],
        onPartial: TranscriptionProgressSink?
    ) async throws -> Transcript {
        guard mode() != "local" else { throw EngineError.localTranscriptionRemoved }
        return try await cloud.transcribe(
            audio, dictionaryTerms: dictionaryTerms, onPartial: onPartial)
    }
}
