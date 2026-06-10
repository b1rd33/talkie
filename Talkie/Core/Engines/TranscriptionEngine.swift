import Foundation

struct Transcript: Sendable, Equatable {
    let text: String
}

enum EngineError: Error, Equatable, LocalizedError {
    case missingAPIKey
    case requestFailed(status: Int, message: String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "API key missing — add it in Settings."
        case .requestFailed(let status, let message): "Request failed (\(status)): \(message)"
        case .invalidResponse: "The API returned an unreadable response."
        }
    }
}

protocol TranscriptionEngine: Sendable {
    func transcribe(_ audio: RecordedAudio, dictionaryTerms: [String]) async throws -> Transcript
}
