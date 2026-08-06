import Foundation

/// Batch transcription via POST /v1/audio/transcriptions (process-on-release, spec §3).
struct OpenAIEngine: TranscriptionEngine {
    var apiKeyProvider: @Sendable () -> String?
    var modelProvider: @Sendable () -> String
    var contextProvider: @Sendable ([String]) -> TranscriptionContext
    var streamProvider: @Sendable () -> Bool
    var speakerFilterProvider: @Sendable () -> SpeakerFilterConfiguration?
    var speakerFilteringEnabledProvider: @Sendable () -> Bool
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
        speakerFilterProvider: @escaping @Sendable () -> SpeakerFilterConfiguration? = { nil },
        speakerFilteringEnabledProvider: @escaping @Sendable () -> Bool = { false },
        session: URLSession = .shared
    ) {
        self.apiKeyProvider = apiKeyProvider
        self.modelProvider = modelProvider
        self.contextProvider = contextProvider
        self.streamProvider = streamProvider
        self.speakerFilterProvider = speakerFilterProvider
        self.speakerFilteringEnabledProvider = speakerFilteringEnabledProvider
        self.session = session
    }

    func transcribe(
        _ audio: RecordedAudio,
        dictionaryTerms: [String],
        onPartial: TranscriptionProgressSink?
    ) async throws -> Transcript {
        guard let key = apiKeyProvider(), !key.isEmpty else { throw EngineError.missingAPIKey }
        let selectedModel = modelProvider()
        let speakerFilteringEnabled = speakerFilteringEnabledProvider()
        let speakerFilter = speakerFilteringEnabled ? speakerFilterProvider() : nil
        guard !speakerFilteringEnabled || speakerFilter != nil else {
            throw EngineError.speakerReferenceMissing
        }
        let model = speakerFilter == nil ? selectedModel : "gpt-4o-transcribe-diarize"
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
        field("response_format", speakerFilter == nil ? "json" : "diarized_json")
        if let speakerFilter {
            field("chunking_strategy", "auto")
            field("known_speaker_names[]", speakerFilter.speakerName)
            let reference = try Data(contentsOf: speakerFilter.referenceURL)
            field(
                "known_speaker_references[]",
                "data:audio/mp4;base64,\(reference.base64EncodedString())")
        } else if OpenAITranscriptionModel(rawValue: model)?.supportsKeywords == true {
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
        let shouldStream = speakerFilter == nil &&
            model == OpenAITranscriptionModel.gptTranscribe.rawValue
            && streamProvider()
        if shouldStream {
            field("stream", "true")
        }
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\nContent-Type: audio/mp4\r\n\r\n".utf8))
        body.append(try Data(contentsOf: audio.fileURL))
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body

        if shouldStream {
            do {
                let (bytes, response) = try await session.bytes(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw EngineError.invalidResponse
                }
                guard (200..<300).contains(http.statusCode) else {
                    throw EngineError.requestFailed(
                        status: http.statusCode,
                        message: "")
                }

                var parser = OpenAISSEParser()
                var accumulated = ""
                var final: Transcript?
                for try await byte in bytes {
                    for event in try parser.append(Data([byte])) {
                        switch event {
                        case .delta(let delta):
                            accumulated += delta
                            onPartial?(accumulated)
                        case .done(let text, let detectedLanguages):
                            final = Transcript(
                                text: text,
                                engineID: model,
                                detectedLanguages: detectedLanguages)
                        }
                    }
                }
                guard let final else {
                    throw EngineError.invalidResponse
                }
                guard !final.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw EngineError.emptyTranscription
                }
                return final
            } catch let urlError as URLError where
                [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
                 .cannotFindHost, .cannotConnectToHost, .timedOut].contains(urlError.code) {
                throw EngineError.offline
            }
        }

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

            struct Segment: Decodable {
                let speaker: String?
                let text: String
            }

            let text: String
            let languages: [Language]?
            let segments: [Segment]?
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw EngineError.invalidResponse
        }
        let text: String
        if let speakerFilter {
            text = decoded.segments?
                .filter { $0.speaker == speakerFilter.speakerName }
                .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ") ?? ""
            guard !text.isEmpty else { throw EngineError.enrolledSpeakerNotDetected }
        } else {
            text = decoded.text
        }
        let transcript = Transcript(
            text: text,
            engineID: model,
            detectedLanguages: decoded.languages?.map(\.code) ?? [])
        guard !transcript.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EngineError.emptyTranscription
        }
        return transcript
    }
}
