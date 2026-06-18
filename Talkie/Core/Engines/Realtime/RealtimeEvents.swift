import Foundation

/// Client→server events for OpenAI Realtime transcription sessions.
/// ⚠️ Wire shapes reconciled against OpenAI's current Realtime docs (2026-06):
/// GA sessions use "session.update" with session.type "transcription" and the
/// transcription config nested under audio.input (model/prompt/language) —
/// the beta-era "transcription_session.update" flat shape is gone.
enum RealtimeClientEvent {
    case sessionUpdate(model: String, vocabulary: String?, language: String?)
    case audioAppend(pcm16: Data)
    case audioCommit

    func encoded() -> Data {
        let payload: [String: Any]
        switch self {
        case .sessionUpdate(let model, let vocabulary, let language):
            var transcription: [String: Any] = ["model": model]
            if let vocabulary { transcription["prompt"] = vocabulary } // spec §3/§6: ASR-level vocabulary biasing
            if let language { transcription["language"] = language }   // spec §3: ISO-639-1 pinned language; absent = auto-detect
            let session: [String: Any] = [
                "type": "transcription",
                "audio": [
                    "input": [
                        "format": ["type": "audio/pcm", "rate": 24_000],
                        "transcription": transcription,
                        // Server VAD segments speech on pauses so the model transcribes
                        // mid-hold (streamed deltas) instead of only after the manual
                        // commit on fn-release. fn still bounds the take; finish() sends
                        // a trailing commit for the last unspoken segment.
                        "turn_detection": [
                            "type": "server_vad",
                            "threshold": 0.5,
                            "prefix_padding_ms": 300,
                            "silence_duration_ms": 250,
                        ],
                    ],
                ],
            ]
            payload = ["type": "session.update", "session": session]
        case .audioAppend(let pcm16):
            payload = ["type": "input_audio_buffer.append", "audio": pcm16.base64EncodedString()]
        case .audioCommit:
            payload = ["type": "input_audio_buffer.commit"]
        }
        return try! JSONSerialization.data(withJSONObject: payload)
    }
}

/// Server→client events we care about; everything else decodes to .ignored.
enum RealtimeServerEvent: Equatable {
    case transcriptDelta(String)
    case transcriptCompleted(String)
    /// A VAD-detected (or manually committed) audio segment was accepted — a
    /// `completed` for that segment will follow. We count these to know when all
    /// in-flight segments have resolved before finishing.
    case segmentCommitted
    /// `input_audio_buffer.commit` rejected because the buffer was empty/too short
    /// (<100ms). Benign on the trailing finish() commit when VAD already drained
    /// everything — not a real error.
    case commitEmpty
    case error(String)
    case ignored(type: String)

    static func decode(_ data: Data) throws -> RealtimeServerEvent {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else {
            throw EngineError.invalidResponse
        }
        switch type {
        case "conversation.item.input_audio_transcription.delta":
            return .transcriptDelta(object["delta"] as? String ?? "")
        case "conversation.item.input_audio_transcription.completed":
            return .transcriptCompleted(object["transcript"] as? String ?? "")
        case "input_audio_buffer.committed":
            return .segmentCommitted
        case "error":
            let errorObject = object["error"] as? [String: Any]
            let code = errorObject?["code"] as? String
            if code == "input_audio_buffer_commit_empty" { return .commitEmpty }
            let message = (errorObject?["message"] as? String) ?? "realtime error"
            return .error(message)
        default:
            return .ignored(type: type)
        }
    }
}
