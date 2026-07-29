import Foundation

/// Batch transcription via POST /v1/audio/transcriptions (process-on-release, spec §3).
struct OpenAIEngine: TranscriptionEngine {
    var apiKeyProvider: @Sendable () -> String?
    var modelProvider: @Sendable () -> String
    var contextProvider: @Sendable ([String]) -> TranscriptionContext
    var streamProvider: @Sendable () -> Bool
    var session: URLSession

    init(
        apiKeyProvider: @escaping @Sendable () -> String?,
        modelProvider: @escaping @Sendable () -> String,
        contextProvider: @escaping @Sendable ([String]) -> TranscriptionContext = {
            TranscriptionContext.build(
                prompt: "",
                dictionaryTerms: $0,
                languageCodes: [])
        },
        streamProvider: @escaping @Sendable () -> Bool = { false },
        session: URLSession = .shared
    ) {
        self.apiKeyProvider = apiKeyProvider
        self.modelProvider = modelProvider
        self.contextProvider = contextProvider
        self.streamProvider = streamProvider
        self.session = session
    }

    func transcribe(_ audio: RecordedAudio, dictionaryTerms: [String]) async throws -> Transcript {
        guard let key = apiKeyProvider(), !key.isEmpty else { throw EngineError.missingAPIKey }
        let model = modelProvider()
        let context = contextProvider(dictionaryTerms)

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
        field("model", model)
        field("response_format", "json")
        if OpenAITranscriptionModel(rawValue: model)?.supportsKeywords == true {
            if let prompt = context.prompt {
                field("prompt", prompt)
            }
            for keyword in context.keywords {
                field("keywords[]", keyword)
            }
            for language in context.languages {
                field("languages[]", language)
            }
        } else {
            if !context.keywords.isEmpty {
                field("prompt", "Vocabulary: " + context.keywords.joined(separator: ", "))
            }
            if let language = context.legacyLanguage {
                field("language", language)
            }
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
        struct Response: Decodable {
            struct Language: Decodable {
                let code: String
            }

            let text: String
            let languages: [Language]?
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw EngineError.invalidResponse
        }
        return Transcript(
            text: decoded.text,
            engineID: model,
            detectedLanguages: decoded.languages?.map(\.code) ?? [])
    }
}
