import XCTest
@testable import Talkie

final class RealtimeEventsTests: XCTestCase {
    func testSessionUpdateEncodes() throws {
        // Wire shape reconciled against OpenAI's current Realtime docs (2026-06):
        // GA uses "session.update" with session.type "transcription" and the
        // transcription config nested under audio.input — NOT the beta-era
        // "transcription_session.update" the plan sketched.
        let event = RealtimeClientEvent.sessionUpdate(model: "gpt-realtime-whisper", vocabulary: "Talkie, Archiev", language: "de")
        let json = try XCTUnwrap(String(data: event.encoded(), encoding: .utf8))
        XCTAssertTrue(json.contains(#""type":"session.update""#))
        XCTAssertTrue(json.contains("gpt-realtime-whisper"))
        XCTAssertTrue(json.contains("Talkie, Archiev"))
        XCTAssertTrue(json.contains(#""language":"de""#)) // spec §3: pinned language reaches the ASR
    }

    func testAudioAppendEncodesBase64() throws {
        let event = RealtimeClientEvent.audioAppend(pcm16: Data([0x01, 0x02]))
        let json = try XCTUnwrap(String(data: event.encoded(), encoding: .utf8))
        XCTAssertTrue(json.contains(#""type":"input_audio_buffer.append""#))
        XCTAssertTrue(json.contains(Data([0x01, 0x02]).base64EncodedString()))
    }

    func testDeltaAndCompletedDecode() throws {
        let delta = try RealtimeServerEvent.decode(Data(#"{"type":"conversation.item.input_audio_transcription.delta","delta":"hel"}"#.utf8))
        guard case .transcriptDelta(let text) = delta else { return XCTFail("wrong case") }
        XCTAssertEqual(text, "hel")

        let done = try RealtimeServerEvent.decode(Data(#"{"type":"conversation.item.input_audio_transcription.completed","transcript":"hello world"}"#.utf8))
        guard case .transcriptCompleted(let transcript) = done else { return XCTFail("wrong case") }
        XCTAssertEqual(transcript, "hello world")
    }

    func testErrorAndUnknownDecode() throws {
        let error = try RealtimeServerEvent.decode(Data(#"{"type":"error","error":{"message":"bad session"}}"#.utf8))
        guard case .error(let message) = error else { return XCTFail("wrong case") }
        XCTAssertTrue(message.contains("bad session"))

        let other = try RealtimeServerEvent.decode(Data(#"{"type":"input_audio_buffer.committed"}"#.utf8))
        guard case .ignored = other else { return XCTFail("wrong case") }
    }
}
