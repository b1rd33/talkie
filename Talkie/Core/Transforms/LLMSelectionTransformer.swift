import Foundation

/// Provider closures read thread-safe system stores such as UserDefaults and
/// Keychain wrappers. Keeping them non-Sendable avoids falsely requiring those
/// Objective-C store objects to conform to Swift's Sendable protocol.
struct LLMSelectionTransformer: SelectionTransforming, @unchecked Sendable {
    var apiKeyProvider: () -> String?
    var modelProvider: () -> String
    var endpointProvider: () -> URL
    var extraPayloadProvider: () -> [String: String] = { [:] }
    var session: URLSession = .shared

    func transform(_ text: String, instruction: String) async throws -> String {
        guard let key = apiKeyProvider(), !key.isEmpty else { throw EngineError.missingAPIKey }
        var request = URLRequest(url: endpointProvider())
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload: [String: Any] = [
            "model": modelProvider(), "temperature": 0.2,
            "messages": [
                ["role": "system", "content": """
                    Transform the selected text using this instruction: \(instruction)
                    Preserve meaning unless the instruction explicitly asks otherwise.
                    Output only the transformed text, with no quotes or commentary.
                    """],
                ["role": "user", "content": text],
            ],
        ]
        for (key, value) in extraPayloadProvider() { payload[key] = value }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw EngineError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw EngineError.requestFailed(status: http.statusCode,
                                            message: String(data: data, encoding: .utf8) ?? "")
        }
        struct Response: Decodable {
            struct Choice: Decodable { struct Message: Decodable { let content: String }; let message: Message }
            let choices: [Choice]
        }
        guard let result = try? JSONDecoder().decode(Response.self, from: data),
              let content = result.choices.first?.message.content else { throw EngineError.invalidResponse }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
