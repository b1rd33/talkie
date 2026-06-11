import Foundation

protocol CleanupServicing: Sendable {
    func clean(_ transcript: String, dictionaryTerms: [String], level: CleanupLevel,
               style: StylePreset, pinnedLanguage: String?) async throws -> String
}

/// One OpenRouter chat completion turns raw ASR text into polished text (spec §6).
/// Callers must not invoke this at CleanupLevel.none — the coordinator skips the
/// LLM entirely and inserts the raw transcript (Task 4).
struct CleanupService: CleanupServicing {
    var apiKeyProvider: @Sendable () -> String?
    var modelProvider: @Sendable () -> String
    var session: URLSession = .shared
    var promptBuilder = PromptBuilder()

    func clean(_ transcript: String, dictionaryTerms: [String], level: CleanupLevel,
               style: StylePreset, pinnedLanguage: String?) async throws -> String {
        guard let key = apiKeyProvider(), !key.isEmpty else { throw EngineError.missingAPIKey }

        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 10 // spec §3: cleanup timeout 10s
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "model": modelProvider(),
            "temperature": 0.2,
            "messages": [
                ["role": "system", "content": promptBuilder.systemPrompt(
                    level: level, style: style, dictionaryTerms: dictionaryTerms,
                    pinnedLanguage: pinnedLanguage)],
                ["role": "user", "content": transcript],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw EngineError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw EngineError.requestFailed(status: http.statusCode,
                                            message: String(data: data, encoding: .utf8) ?? "")
        }
        struct Response: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data),
              let content = decoded.choices.first?.message.content else {
            throw EngineError.invalidResponse
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
