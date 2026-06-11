import XCTest
@testable import Talkie

final class OpenAIRealtimeSessionTests: XCTestCase {
    /// Scripted transport: hands out queued server events; records sent client events.
    /// Server events are held back until the client commits — without the gate the
    /// receive loop (spawned in begin()) can drain the whole inbox, including
    /// `completed`, before the test's feed() acquires the actor, and feed's
    /// `completedTranscript == nil` guard would then skip the append the test asserts.
    final class FakeTransport: RealtimeTransport, @unchecked Sendable {
        let lock = NSLock()
        var sent: [String] = []
        var inbox: [Data] = []
        var connectError: Error?
        private var committed = false
        private var receiveIndex = 0

        func connect() async throws { if let connectError { throw connectError } }
        func send(_ data: Data) async throws {
            let text = String(decoding: data, as: UTF8.self)
            lock.lock()
            sent.append(text)
            if text.contains("input_audio_buffer.commit") { committed = true }
            lock.unlock()
        }
        func receive() async throws -> Data {
            while true {
                lock.lock()
                if committed, receiveIndex < inbox.count {
                    let next = inbox[receiveIndex]; receiveIndex += 1
                    lock.unlock()
                    return next
                }
                lock.unlock()
                // parks until commit (or until cleanup() cancels the receive loop)
                try await Task.sleep(for: .milliseconds(2))
            }
        }
        func close() {}
    }

    func testHappyPathAccumulatesAndFinishes() async throws {
        let transport = FakeTransport()
        transport.inbox = [
            Data(#"{"type":"input_audio_buffer.committed"}"#.utf8),
            Data(#"{"type":"conversation.item.input_audio_transcription.delta","delta":"hello "}"#.utf8),
            Data(#"{"type":"conversation.item.input_audio_transcription.completed","transcript":"hello world"}"#.utf8),
        ]
        let session = OpenAIRealtimeSession(transport: transport, model: "gpt-realtime-whisper",
                                            vocabulary: nil, language: nil,
                                            encoder: RealtimePCMEncoder(inputRate: 24_000, outputRate: 24_000))
        try await session.begin()
        await session.feed([0.1, 0.2, 0.3])
        let transcript = try await session.finish()
        XCTAssertEqual(transcript.text, "hello world")
        XCTAssertEqual(transcript.engineID, "realtime")
        let sent = transport.sent
        XCTAssertTrue(sent[0].contains("session.update"))
        XCTAssertTrue(sent.contains { $0.contains("input_audio_buffer.append") })
        XCTAssertTrue(sent.last!.contains("input_audio_buffer.commit"))
    }

    func testServerErrorSurfacesFromFinish() async throws {
        let transport = FakeTransport()
        transport.inbox = [Data(#"{"type":"error","error":{"message":"session expired"}}"#.utf8)]
        let session = OpenAIRealtimeSession(transport: transport, model: "m", vocabulary: nil, language: nil,
                                            encoder: RealtimePCMEncoder(inputRate: 24_000, outputRate: 24_000))
        try await session.begin()
        do {
            _ = try await session.finish()
            XCTFail("expected throw")
        } catch let error as EngineError {
            guard case .requestFailed(_, let message) = error else { return XCTFail("wrong case: \(error)") }
            XCTAssertTrue(message.contains("session expired"))
        } catch { XCTFail("wrong error: \(error)") }
    }

    func testConnectFailureThrowsFromBegin() async {
        let transport = FakeTransport()
        transport.connectError = EngineError.offline
        let session = OpenAIRealtimeSession(transport: transport, model: "m", vocabulary: nil, language: nil,
                                            encoder: RealtimePCMEncoder(inputRate: 24_000, outputRate: 24_000))
        do {
            try await session.begin()
            XCTFail("expected throw")
        } catch let error as EngineError {
            XCTAssertEqual(error, .offline)
        } catch { XCTFail("wrong error: \(error)") }
    }
}
