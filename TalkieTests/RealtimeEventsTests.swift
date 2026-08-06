import XCTest
@testable import Talkie

final class RealtimeEventsTests: XCTestCase {
    func testNewLiveSessionUpdateEncodesContextAndDelay() throws {
        let event = RealtimeClientEvent.sessionUpdate(
            model: "gpt-live-transcribe",
            context: TranscriptionContext(
                prompt: "Talkie demo",
                keywords: ["Talkie", "AC-42"],
                languages: ["en", "de"]),
            delay: .low)

        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: event.encoded()) as? [String: Any])
        let session = try XCTUnwrap(root["session"] as? [String: Any])
        let audio = try XCTUnwrap(session["audio"] as? [String: Any])
        let input = try XCTUnwrap(audio["input"] as? [String: Any])
        let transcription = try XCTUnwrap(
            input["transcription"] as? [String: Any])
        XCTAssertEqual(transcription["model"] as? String, "gpt-live-transcribe")
        XCTAssertEqual(transcription["prompt"] as? String, "Talkie demo")
        XCTAssertEqual(
            transcription["keywords"] as? [String],
            ["Talkie", "AC-42"])
        XCTAssertEqual(
            transcription["languages"] as? [String],
            ["en", "de"])
        XCTAssertEqual(transcription["delay"] as? String, "low")
        XCTAssertNil(transcription["language"])
        XCTAssertTrue(input["turn_detection"] is NSNull)
    }

    func testRealtimeWhisperSessionUpdateDisablesTurnDetection() throws {
        let event = RealtimeClientEvent.sessionUpdate(
            model: "gpt-realtime-whisper",
            context: TranscriptionContext(prompt: nil, keywords: [], languages: []),
            delay: .medium)

        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: event.encoded()) as? [String: Any])
        let session = try XCTUnwrap(root["session"] as? [String: Any])
        let audio = try XCTUnwrap(session["audio"] as? [String: Any])
        let input = try XCTUnwrap(audio["input"] as? [String: Any])

        XCTAssertTrue(input["turn_detection"] is NSNull)
    }

    func testLegacySessionUpdateFoldsKeywordsIntoPromptAndKeepsSingularLanguage() throws {
        let event = RealtimeClientEvent.sessionUpdate(
            model: "gpt-realtime-whisper",
            context: TranscriptionContext(
                prompt: "Meeting notes",
                keywords: ["Talkie", "Archiev"],
                languages: ["de", "en"]),
            delay: .low)

        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: event.encoded()) as? [String: Any])
        let session = try XCTUnwrap(root["session"] as? [String: Any])
        let audio = try XCTUnwrap(session["audio"] as? [String: Any])
        let input = try XCTUnwrap(audio["input"] as? [String: Any])
        let transcription = try XCTUnwrap(
            input["transcription"] as? [String: Any])
        XCTAssertEqual(
            transcription["prompt"] as? String,
            "Meeting notes\nVocabulary: Talkie, Archiev")
        XCTAssertEqual(transcription["language"] as? String, "de")
        XCTAssertNil(transcription["keywords"])
        XCTAssertNil(transcription["languages"])
        XCTAssertNil(transcription["delay"])
    }

    func testLegacySessionUpdateUsesVocabularyPromptWhenNoPromptExists() throws {
        let event = RealtimeClientEvent.sessionUpdate(
            model: "gpt-realtime-whisper",
            context: TranscriptionContext(
                prompt: nil,
                keywords: ["Talkie", "Archiev"],
                languages: []),
            delay: .medium)

        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: event.encoded()) as? [String: Any])
        let session = try XCTUnwrap(root["session"] as? [String: Any])
        let audio = try XCTUnwrap(session["audio"] as? [String: Any])
        let input = try XCTUnwrap(audio["input"] as? [String: Any])
        let transcription = try XCTUnwrap(input["transcription"] as? [String: Any])
        XCTAssertEqual(
            transcription["prompt"] as? String,
            "Vocabulary: Talkie, Archiev")
    }

    func testAudioAppendEncodesBase64() throws {
        let event = RealtimeClientEvent.audioAppend(pcm16: Data([0x01, 0x02]))
        let json = try XCTUnwrap(String(data: event.encoded(), encoding: .utf8))
        XCTAssertTrue(json.contains(#""type":"input_audio_buffer.append""#))
        XCTAssertTrue(json.contains(Data([0x01, 0x02]).base64EncodedString()))
    }

    func testAudioCommitEncodesClientEventID() throws {
        let json = try XCTUnwrap(String(
            data: RealtimeClientEvent.audioCommit(eventID: "finish-123").encoded(),
            encoding: .utf8))
        XCTAssertTrue(json.contains(#""type":"input_audio_buffer.commit""#))
        XCTAssertTrue(json.contains(#""event_id":"finish-123""#))
    }

    func testDeltaAndCompletedDecode() throws {
        let delta = try RealtimeServerEvent.decode(Data(#"{"type":"conversation.item.input_audio_transcription.delta","item_id":"item-1","delta":"hel"}"#.utf8))
        guard case .transcriptDelta(let itemID, let text) = delta else { return XCTFail("wrong case") }
        XCTAssertEqual(itemID, "item-1")
        XCTAssertEqual(text, "hel")

        let done = try RealtimeServerEvent.decode(Data(#"{"type":"conversation.item.input_audio_transcription.completed","item_id":"item-1","transcript":"hello world","languages":[{"code":"en"}]}"#.utf8))
        guard case .transcriptCompleted(
            let itemID, let transcript, let detectedLanguages
        ) = done else { return XCTFail("wrong case") }
        XCTAssertEqual(itemID, "item-1")
        XCTAssertEqual(transcript, "hello world")
        XCTAssertEqual(detectedLanguages, ["en"])
    }

    func testErrorAndUnknownDecode() throws {
        let error = try RealtimeServerEvent.decode(Data(#"{"type":"error","error":{"message":"bad session"}}"#.utf8))
        guard case .error(let message, clientEventID: nil) = error else { return XCTFail("wrong case") }
        XCTAssertTrue(message.contains("bad session"))

        // speech_started/stopped carry no transcript — still ignored.
        let other = try RealtimeServerEvent.decode(Data(#"{"type":"input_audio_buffer.speech_started"}"#.utf8))
        guard case .ignored = other else { return XCTFail("wrong case") }
    }

    func testSegmentCommittedDecodes() throws {
        let event = try RealtimeServerEvent.decode(Data(#"{"type":"input_audio_buffer.committed","item_id":"item-42"}"#.utf8))
        guard case .segmentCommitted(let itemID) = event else { return XCTFail("expected .segmentCommitted, got \(event)") }
        XCTAssertEqual(itemID, "item-42")
    }

    func testCommitEmptyErrorDecodesSeparately() throws {
        // The trailing finish() commit on an already-drained buffer — benign, not a real error.
        let empty = try RealtimeServerEvent.decode(Data(#"{"type":"error","error":{"code":"input_audio_buffer_commit_empty","message":"buffer too small","event_id":"finish-123"}}"#.utf8))
        guard case .commitEmpty(clientEventID: "finish-123") = empty else { return XCTFail("expected .commitEmpty, got \(empty)") }

        // A different error code still surfaces as a real error.
        let real = try RealtimeServerEvent.decode(Data(#"{"type":"error","error":{"code":"session_expired","message":"session expired"}}"#.utf8))
        guard case .error(let message, clientEventID: nil) = real else { return XCTFail("expected .error, got \(real)") }
        XCTAssertTrue(message.contains("session expired"))
    }

    func testTranscriptionFailureRetainsItemID() throws {
        let failed = try RealtimeServerEvent.decode(Data(#"{"type":"conversation.item.input_audio_transcription.failed","item_id":"item-9","error":{"message":"unintelligible"}}"#.utf8))
        guard case .transcriptionFailed(let itemID, let message) = failed else {
            return XCTFail("expected transcription failure, got \(failed)")
        }
        XCTAssertEqual(itemID, "item-9")
        XCTAssertEqual(message, "unintelligible")
    }
}
