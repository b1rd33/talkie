import Foundation

/// Batch transcription via POST /v1/audio/transcriptions (process-on-release, spec §3).
struct OpenAIEngine: TranscriptionEngine {
    var apiKeyProvider: @Sendable () -> String?
    var modelProvider: @Sendable () -> String
    var session: URLSession = .shared

    func transcribe(_ audio: RecordedAudio, dictionaryTerms: [String]) async throws -> Transcript {
        guard let key = apiKeyProvider(), !key.isEmpty else { throw EngineError.missingAPIKey }

        let boundary = "talkie-\(UUID().uuidString)"
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        field("model", modelProvider())
        field("response_format", "json")
        if !dictionaryTerms.isEmpty {
            // Terms are interpolated into a multipart text field — CR/LF would break framing.
            let sanitized = dictionaryTerms.map {
                $0.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
            }
            field("prompt", "Vocabulary: " + sanitized.joined(separator: ", "))
        }
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\nContent-Type: audio/mp4\r\n\r\n".utf8))
        body.append(try Data(contentsOf: audio.fileURL))
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body

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
        return Transcript(text: decoded.text)
    }
}
