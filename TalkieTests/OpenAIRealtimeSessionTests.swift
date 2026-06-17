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

    func testPartialSinkReceivesCumulativeDeltas() async throws {
        let transport = FakeTransport()
        transport.inbox = [
            Data(#"{"type":"input_audio_buffer.committed"}"#.utf8),
            Data(#"{"type":"conversation.item.input_audio_transcription.delta","delta":"hello "}"#.utf8),
            Data(#"{"type":"conversation.item.input_audio_transcription.delta","delta":"world"}"#.utf8),
            Data(#"{"type":"conversation.item.input_audio_transcription.completed","transcript":"hello world"}"#.utf8),
        ]
        let lock = NSLock()
        var partials: [String] = []
        let done = expectation(description: "completed echo")
        let session = OpenAIRealtimeSession(transport: transport, model: "m", vocabulary: nil, language: nil,
                                            encoder: RealtimePCMEncoder(inputRate: 24_000, outputRate: 24_000),
                                            onPartial: { s in
                                                lock.lock(); partials.append(s); let n = partials.count; lock.unlock()
                                                if n == 3 { done.fulfill() }
                                            })
        try await session.begin()
        await session.feed([0.1, 0.2, 0.3])
        _ = try await session.finish()
        await fulfillment(of: [done], timeout: 2)
        lock.lock(); let captured = partials; lock.unlock()
        XCTAssertEqual(captured, ["hello ", "hello world", "hello world"]) // cumulative + completed echo
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

    /// VAD-aware transport: delivers `streamInbox` immediately (segments transcribed
    /// mid-hold) and `commitInbox` only after the client's trailing commit (the
    /// segment after the last pause). Models the real server_vad event timing.
    final class StreamingFakeTransport: RealtimeTransport, @unchecked Sendable {
        let lock = NSLock()
        var sent: [String] = []
        var streamInbox: [Data] = []
        var commitInbox: [Data] = []
        private var committed = false
        private var streamIndex = 0
        private var commitIndex = 0

        func connect() async throws {}
        func send(_ data: Data) async throws {
            let text = String(decoding: data, as: UTF8.self)
            lock.lock()
            sent.append(text)
            if text.contains(#""input_audio_buffer.commit""#) { committed = true }
            lock.unlock()
        }
        func receive() async throws -> Data {
            while true {
                lock.lock()
                if streamIndex < streamInbox.count {
                    let next = streamInbox[streamIndex]; streamIndex += 1; lock.unlock(); return next
                }
                if committed, commitIndex < commitInbox.count {
                    let next = commitInbox[commitIndex]; commitIndex += 1; lock.unlock(); return next
                }
                lock.unlock()
                try await Task.sleep(for: .milliseconds(2))
            }
        }
        func close() {}
    }

    private static func delta(_ s: String) -> Data { Data(#"{"type":"conversation.item.input_audio_transcription.delta","delta":"\#(s)"}"#.utf8) }
    private static func completed(_ s: String) -> Data { Data(#"{"type":"conversation.item.input_audio_transcription.completed","transcript":"\#(s)"}"#.utf8) }
    private static let committedEvent = Data(#"{"type":"input_audio_buffer.committed"}"#.utf8)
    private static let commitEmptyEvent = Data(#"{"type":"error","error":{"code":"input_audio_buffer_commit_empty","message":"buffer too small"}}"#.utf8)

    /// Two VAD segments — one streamed mid-hold, one flushed by finish()'s trailing
    /// commit — concatenate in order, and onPartial grows monotonically across them.
    func testMultipleVADSegmentsConcatenateAcrossFinish() async throws {
        let transport = StreamingFakeTransport()
        transport.streamInbox = [Self.committedEvent, Self.delta("Hello"), Self.completed("Hello")]
        transport.commitInbox = [Self.committedEvent, Self.delta(" world"), Self.completed("world")]
        let lock = NSLock(); var partials: [String] = []
        let sawSegment1 = expectation(description: "segment 1 streamed mid-hold")
        sawSegment1.assertForOverFulfill = false // "Hello" is emitted on its delta and again on its completed
        let session = OpenAIRealtimeSession(transport: transport, model: "m", vocabulary: nil, language: nil,
                                            encoder: RealtimePCMEncoder(inputRate: 24_000, outputRate: 24_000),
                                            onPartial: { s in
                                                lock.lock(); partials.append(s); lock.unlock()
                                                if s == "Hello" { sawSegment1.fulfill() }
                                            })
        try await session.begin()
        await session.feed([0.1, 0.2, 0.3])
        await fulfillment(of: [sawSegment1], timeout: 2) // ensure segment 1 lands before finish()
        let transcript = try await session.finish()
        XCTAssertEqual(transcript.text, "Hello world")
        lock.lock(); let captured = partials; lock.unlock()
        XCTAssertEqual(captured.first, "Hello")
        XCTAssertEqual(captured.last, "Hello world")
        // monotonic prefix growth — never shrinks
        for (a, b) in zip(captured, captured.dropFirst()) { XCTAssertTrue(b.hasPrefix(a) || b.count >= a.count) }
    }

    /// finish()'s trailing commit on an already-drained buffer returns an empty-commit
    /// error — that must NOT throw; the accumulated segments are returned.
    func testCommitEmptyOnFinishReturnsAccumulated() async throws {
        let transport = StreamingFakeTransport()
        transport.streamInbox = [Self.committedEvent, Self.delta("Hello world"), Self.completed("Hello world")]
        transport.commitInbox = [Self.commitEmptyEvent]
        let sawSegment = expectation(description: "segment streamed mid-hold")
        sawSegment.assertForOverFulfill = false // emitted on its delta and again on its completed
        let session = OpenAIRealtimeSession(transport: transport, model: "m", vocabulary: nil, language: nil,
                                            encoder: RealtimePCMEncoder(inputRate: 24_000, outputRate: 24_000),
                                            onPartial: { if $0 == "Hello world" { sawSegment.fulfill() } })
        try await session.begin()
        await session.feed([0.1, 0.2, 0.3])
        await fulfillment(of: [sawSegment], timeout: 2)
        let transcript = try await session.finish()
        XCTAssertEqual(transcript.text, "Hello world") // no throw on empty trailing commit
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
