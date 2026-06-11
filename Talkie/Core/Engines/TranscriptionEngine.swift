import Foundation

struct Transcript: Sendable, Equatable {
    let text: String
    var engineID: String = "openai"
    var usedFallback: Bool = false
}

enum EngineError: Error, Equatable, LocalizedError {
    case missingAPIKey
    case requestFailed(status: Int, message: String)
    case invalidResponse
    case offline

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "API key missing — add it in Settings."
        case .requestFailed(let status, let message): "Request failed (\(status)): \(message)"
        case .invalidResponse: "The API returned an unreadable response."
        case .offline: "No internet connection."
        }
    }
}

protocol TranscriptionEngine: Sendable {
    func transcribe(_ audio: RecordedAudio, dictionaryTerms: [String]) async throws -> Transcript
}
