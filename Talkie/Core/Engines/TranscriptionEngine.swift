import Foundation

struct Transcript: Sendable, Equatable {
    let text: String
    var engineID: String = "openai"
    var usedFallback: Bool = false
    var detectedLanguages: [String] = []
}

enum RealtimeFailureCategory: String, Equatable, Sendable {
    case serverError
    case transcriptionError
    case connectionLost
    case timeout
    case transportFailure
}

enum EngineError: Error, Equatable, LocalizedError {
    case missingAPIKey
    case localModelsUnavailable
    case requestFailed(status: Int, message: String)
    case invalidResponse
    case emptyTranscription
    case speakerReferenceMissing
    case enrolledSpeakerNotDetected
    case realtimeFailure(RealtimeFailureCategory)
    case offline

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "API key missing — add it in Settings."
        case .localModelsUnavailable:
            "On-device models aren't downloaded. Download them in Settings → Engines, or explicitly switch to Cloud or Instant."
        case .requestFailed(let status, let message): "Request failed (\(status)): \(message)"
        case .invalidResponse: "The API returned an unreadable response."
        case .emptyTranscription: "The transcription service returned no text."
        case .speakerReferenceMissing:
            "Speaker filtering needs a voice sample — record one in Settings → Engines."
        case .enrolledSpeakerNotDetected:
            "Your enrolled voice wasn't detected in this recording."
        case .realtimeFailure: "Realtime transcription failed."
        case .offline: "No internet connection."
        }
    }
}

typealias TranscriptionProgressSink = @Sendable (String) -> Void

protocol TranscriptionEngine: Sendable {
    func transcribe(
        _ audio: RecordedAudio,
        dictionaryTerms: [String],
        onPartial: TranscriptionProgressSink?
    ) async throws -> Transcript
}

extension TranscriptionEngine {
    func transcribe(
        _ audio: RecordedAudio,
        dictionaryTerms: [String]
    ) async throws -> Transcript {
        try await transcribe(
            audio,
            dictionaryTerms: dictionaryTerms,
            onPartial: nil)
    }
}
