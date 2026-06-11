import Foundation

/// Batch transcription via OpenRouter's transcription endpoint.
/// Wire shape (live-verified 2026-06-11): POST /api/v1/audio/transcriptions with
/// JSON {"model": ..., "input_audio": {"data": <base64>, "format": "m4a"}} —
/// NOT OpenAI multipart. Response is OpenAI-style {"text": ...} (+ usage.cost).
/// Models: mistralai/voxtral-mini-transcribe ($0.003/min),
/// microsoft/mai-transcribe-1.5 ($0.006/min), or any OpenRouter transcription model.
/// Delegates cloud batch transcription per Settings → "Cloud transcription via"
/// at call time (same UserDefaults-at-call pattern as the cleanup provider).
struct CloudEngineSwitch: TranscriptionEngine {
    let openai: TranscriptionEngine
    let openrouter: TranscriptionEngine

    func transcribe(_ audio: RecordedAudio, dictionaryTerms: [String]) async throws -> Transcript {
        let provider = UserDefaults.standard.string(forKey: "transcriptionProvider") ?? "openai"
        let engine = provider == "openrouter" ? openrouter : openai
        return try await engine.transcribe(audio, dictionaryTerms: dictionaryTerms)
    }
}

struct OpenRouterTranscriptionEngine: TranscriptionEngine {
    var apiKeyProvider: @Sendable () -> String?
    var modelProvider: @Sendable () -> String
    var session: URLSession = .shared

    func transcribe(_ audio: RecordedAudio, dictionaryTerms: [String]) async throws -> Transcript {
        guard let key = apiKeyProvider(), !key.isEmpty else { throw EngineError.missingAPIKey }
        let model = modelProvider()

        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Dictionary terms are not biasable on this endpoint (no prompt field) —
        // they're enforced at cleanup, same as the local engine (spec §6).
        let payload: [String: Any] = [
            "model": model,
            "input_audio": [
                "data": try Data(contentsOf: audio.fileURL).base64EncodedString(),
                "format": "m4a", // live-verified accepted (mp4 also works)
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError where
            [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .cannotFindHost,
             .cannotConnectToHost, .timedOut].contains(urlError.code) {
            throw EngineError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw EngineError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw EngineError.requestFailed(status: http.statusCode,
                                            message: String(data: data, encoding: .utf8) ?? "")
        }
        struct Response: Decodable { let text: String }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw EngineError.invalidResponse
        }
        return Transcript(text: decoded.text, engineID: model)
    }
}
