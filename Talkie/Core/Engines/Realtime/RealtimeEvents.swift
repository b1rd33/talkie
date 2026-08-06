import Foundation

/// Client→server events for OpenAI Realtime transcription sessions.
/// ⚠️ Wire shapes reconciled against OpenAI's current Realtime docs (2026-06):
/// GA sessions use "session.update" with session.type "transcription" and the
/// transcription config nested under audio.input (model/prompt/language) —
/// the beta-era "transcription_session.update" flat shape is gone.
enum RealtimeClientEvent {
    case sessionUpdate(
        model: String,
        context: TranscriptionContext,
        delay: RealtimeTranscriptionDelay
    )
    case audioAppend(pcm16: Data)
    case audioCommit(eventID: String)

    func encoded() -> Data {
        let payload: [String: Any]
        switch self {
        case .sessionUpdate(let model, let context, let delay):
            var transcription: [String: Any] = ["model": model]
            let capabilities = OpenAITranscriptionModel(rawValue: model)
            if capabilities?.supportsKeywords == true {
                if let prompt = context.prompt {
                    transcription["prompt"] = prompt
                }
                if !context.keywords.isEmpty {
                    transcription["keywords"] = context.keywords
                }
                if !context.languages.isEmpty {
                    transcription["languages"] = context.languages
                }
                if capabilities?.supportsDelay == true {
                    transcription["delay"] = delay.rawValue
                }
            } else {
                let vocabularyPrompt = context.keywords.isEmpty
                    ? nil
                    : "Vocabulary: \(context.keywords.joined(separator: ", "))"
                let legacyPrompt = [context.prompt, vocabularyPrompt]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
                if !legacyPrompt.isEmpty {
                    transcription["prompt"] = legacyPrompt
                }
                if let language = context.legacyLanguage {
                    transcription["language"] = language
                }
            }
            let turnDetection: Any = capabilities == .gptRealtimeWhisper
                ? NSNull()
                : [
                    "type": "server_vad",
                    "threshold": 0.5,
                    "prefix_padding_ms": 300,
                    "silence_duration_ms": 250,
                ]
            let session: [String: Any] = [
                "type": "transcription",
                "audio": [
                    "input": [
                        "format": ["type": "audio/pcm", "rate": 24_000],
                        "transcription": transcription,
                        // gpt-realtime-whisper requires turn detection to be null;
                        // gpt-live-transcribe uses server VAD for streaming deltas.
                        "turn_detection": turnDetection,
                    ],
                ],
            ]
            payload = ["type": "session.update", "session": session]
        case .audioAppend(let pcm16):
            payload = ["type": "input_audio_buffer.append", "audio": pcm16.base64EncodedString()]
        case .audioCommit(let eventID):
            payload = ["type": "input_audio_buffer.commit", "event_id": eventID]
        }
        return try! JSONSerialization.data(withJSONObject: payload)
    }
}

/// Server→client events we care about; everything else decodes to .ignored.
enum RealtimeServerEvent: Equatable {
    case transcriptDelta(itemID: String, delta: String)
    case transcriptCompleted(
        itemID: String,
        transcript: String,
        detectedLanguages: [String]
    )
    case transcriptionFailed(itemID: String, message: String)
    /// A VAD-detected (or manually committed) audio segment was accepted — a
    /// `completed` for that segment will follow. We count these to know when all
    /// in-flight segments have resolved before finishing.
    case segmentCommitted(itemID: String)
    /// `input_audio_buffer.commit` rejected because the buffer was empty/too short
    /// (<100ms). Benign on the trailing finish() commit when VAD already drained
    /// everything — not a real error.
    case commitEmpty(clientEventID: String?)
    case error(String, clientEventID: String?)
    case ignored(type: String)

    static func decode(_ data: Data) throws -> RealtimeServerEvent {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else {
            throw EngineError.invalidResponse
        }
        switch type {
        case "conversation.item.input_audio_transcription.delta":
            guard let itemID = object["item_id"] as? String else { throw EngineError.invalidResponse }
            return .transcriptDelta(itemID: itemID, delta: object["delta"] as? String ?? "")
        case "conversation.item.input_audio_transcription.completed":
            guard let itemID = object["item_id"] as? String else { throw EngineError.invalidResponse }
            let detectedLanguages = (object["languages"] as? [[String: Any]])?
                .compactMap { $0["code"] as? String } ?? []
            return .transcriptCompleted(itemID: itemID,
                                        transcript: object["transcript"] as? String ?? "",
                                        detectedLanguages: detectedLanguages)
        case "conversation.item.input_audio_transcription.failed":
            guard let itemID = object["item_id"] as? String else { throw EngineError.invalidResponse }
            let errorObject = object["error"] as? [String: Any]
            return .transcriptionFailed(itemID: itemID,
                                        message: errorObject?["message"] as? String ?? "transcription failed")
        case "input_audio_buffer.committed":
            guard let itemID = object["item_id"] as? String else { throw EngineError.invalidResponse }
            return .segmentCommitted(itemID: itemID)
        case "error":
            let errorObject = object["error"] as? [String: Any]
            let code = errorObject?["code"] as? String
            let clientEventID = errorObject?["event_id"] as? String
            if code == "input_audio_buffer_commit_empty" {
                return .commitEmpty(clientEventID: clientEventID)
            }
            let message = (errorObject?["message"] as? String) ?? "realtime error"
            return .error(message, clientEventID: clientEventID)
        default:
            return .ignored(type: type)
        }
    }
}
