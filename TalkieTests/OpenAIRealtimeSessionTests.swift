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
        var disconnectAfterInbox = false
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
                if committed, disconnectAfterInbox {
                    lock.unlock()
                    throw EngineError.offline
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
            Self.committed("item-1"),
            Self.delta("hello ", itemID: "item-1"),
            Self.completed("hello world", itemID: "item-1"),
        ]
        let session = OpenAIRealtimeSession(transport: transport, model: "gpt-realtime-whisper",
                                            vocabulary: nil, language: nil,
                                            encoder: RealtimePCMEncoder(inputRate: 24_000, outputRate: 24_000))
        try await session.begin()
        await session.feed([0.1, 0.2, 0.3])
        let transcript = try await session.finish()
        XCTAssertEqual(transcript.text, "hello world")
        XCTAssertEqual(transcript.engineID, "gpt-realtime-whisper")
        let sent = transport.sent
        XCTAssertTrue(sent[0].contains("session.update"))
        XCTAssertTrue(sent.contains { $0.contains("input_audio_buffer.append") })
        XCTAssertTrue(sent.last!.contains("input_audio_buffer.commit"))
    }

    func testPartialSinkReceivesCumulativeDeltas() async throws {
        let transport = FakeTransport()
        transport.inbox = [
            Self.committed("item-1"),
            Self.delta("hello ", itemID: "item-1"),
            Self.delta("world", itemID: "item-1"),
            Self.completed("hello world", itemID: "item-1"),
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
        var commitDelaysMS: [Int] = []
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
                    let index = commitIndex
                    let next = commitInbox[index]
                    commitIndex += 1
                    let delay = index < commitDelaysMS.count ? commitDelaysMS[index] : 0
                    lock.unlock()
                    if delay > 0 { try await Task.sleep(for: .milliseconds(delay)) }
                    return next
                }
                lock.unlock()
                try await Task.sleep(for: .milliseconds(2))
            }
        }
        func close() {}
    }

    private static func delta(_ s: String, itemID: String) -> Data {
        Data(#"{"type":"conversation.item.input_audio_transcription.delta","item_id":"\#(itemID)","delta":"\#(s)"}"#.utf8)
    }
    private static func completed(
        _ s: String,
        itemID: String,
        languages: [String] = []
    ) -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "type": "conversation.item.input_audio_transcription.completed",
            "item_id": itemID,
            "transcript": s,
            "languages": languages.map { ["code": $0] },
        ])
    }
    private static func committed(_ itemID: String) -> Data {
        Data(#"{"type":"input_audio_buffer.committed","item_id":"\#(itemID)"}"#.utf8)
    }
    private static func commitEmpty(clientEventID: String) -> Data {
        Data(#"{"type":"error","error":{"code":"input_audio_buffer_commit_empty","message":"buffer too small","event_id":"\#(clientEventID)"}}"#.utf8)
    }
    private static func failed(_ message: String, itemID: String) -> Data {
        Data(#"{"type":"conversation.item.input_audio_transcription.failed","item_id":"\#(itemID)","error":{"message":"\#(message)"}}"#.utf8)
    }

    /// Two VAD segments — one streamed mid-hold, one flushed by finish()'s trailing
    /// commit — concatenate in order, and onPartial grows monotonically across them.
    func testMultipleVADSegmentsConcatenateAcrossFinish() async throws {
        let transport = StreamingFakeTransport()
        transport.streamInbox = [Self.committed("item-1"), Self.delta("Hello", itemID: "item-1"), Self.completed("Hello", itemID: "item-1")]
        transport.commitInbox = [Self.committed("item-2"), Self.delta(" world", itemID: "item-2"), Self.completed("world", itemID: "item-2")]
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
        transport.streamInbox = [Self.committed("item-1"), Self.delta("Hello world", itemID: "item-1"), Self.completed("Hello world", itemID: "item-1")]
        transport.commitInbox = [Self.commitEmpty(clientEventID: "finish-test")]
        let sawSegment = expectation(description: "segment streamed mid-hold")
        sawSegment.assertForOverFulfill = false // emitted on its delta and again on its completed
        let session = OpenAIRealtimeSession(transport: transport, model: "m", vocabulary: nil, language: nil,
                                            encoder: RealtimePCMEncoder(inputRate: 24_000, outputRate: 24_000),
                                            onPartial: { if $0 == "Hello world" { sawSegment.fulfill() } },
                                            eventIDProvider: { "finish-test" })
        try await session.begin()
        await session.feed([0.1, 0.2, 0.3])
        await fulfillment(of: [sawSegment], timeout: 2)
        let transcript = try await session.finish()
        XCTAssertEqual(transcript.text, "Hello world") // no throw on empty trailing commit
    }

    func testOutOfOrderCompletionsPreserveCommitOrder() async throws {
        let transport = StreamingFakeTransport()
        transport.commitInbox = [
            Self.committed("item-1"), Self.committed("item-2"),
            Self.completed("second", itemID: "item-2", languages: ["de"]),
            Self.completed("first", itemID: "item-1", languages: ["en"]),
        ]
        let session = OpenAIRealtimeSession(
            transport: transport, model: "m", vocabulary: nil, language: nil,
            encoder: RealtimePCMEncoder(inputRate: 24_000, outputRate: 24_000),
            settlingInterval: .milliseconds(20), finishTimeout: .seconds(1))
        try await session.begin()

        let transcript = try await session.finish()

        XCTAssertEqual(transcript.text, "first second")
        XCTAssertEqual(transcript.detectedLanguages, ["en", "de"])
    }

    func testDelayedCommitWithinSettlingWindowIsDrained() async throws {
        let transport = StreamingFakeTransport()
        transport.commitInbox = [
            Self.committed("vad-item"),
            Self.completed("first", itemID: "vad-item"),
            Self.committed("finish-item"),
            Self.completed("second", itemID: "finish-item"),
        ]
        transport.commitDelaysMS = [0, 0, 30, 0]
        let session = OpenAIRealtimeSession(
            transport: transport, model: "m", vocabulary: nil, language: nil,
            encoder: RealtimePCMEncoder(inputRate: 24_000, outputRate: 24_000),
            settlingInterval: .milliseconds(80), finishTimeout: .seconds(1))
        try await session.begin()

        let transcript = try await session.finish()

        XCTAssertEqual(transcript.text, "first second")
    }

    func testDelayedManualCommitBeyondLegacySettlingWindowIsDrained() async throws {
        let transport = StreamingFakeTransport()
        transport.commitInbox = [
            Self.committed("delayed-vad-item"),
            Self.completed("first", itemID: "delayed-vad-item"),
            Self.committed("manual-finish-item"),
            Self.completed("second", itemID: "manual-finish-item"),
        ]
        transport.commitDelaysMS = [0, 0, 300, 0]
        let session = OpenAIRealtimeSession(
            transport: transport, model: "m", vocabulary: nil, language: nil,
            encoder: RealtimePCMEncoder(inputRate: 24_000, outputRate: 24_000),
            finishTimeout: .seconds(2))
        try await session.begin()

        let transcript = try await session.finish()

        XCTAssertEqual(transcript.text, "first second")
    }

    func testDuplicateEventsDoNotDuplicateTranscript() async throws {
        let transport = StreamingFakeTransport()
        transport.commitInbox = [
            Self.committed("item-1"), Self.committed("item-1"),
            Self.completed("hello", itemID: "item-1"),
            Self.completed("hello", itemID: "item-1"),
        ]
        let session = OpenAIRealtimeSession(
            transport: transport, model: "m", vocabulary: nil, language: nil,
            encoder: RealtimePCMEncoder(inputRate: 24_000, outputRate: 24_000),
            settlingInterval: .milliseconds(20), finishTimeout: .seconds(1))
        try await session.begin()
        let transcript = try await session.finish()
        XCTAssertEqual(transcript.text, "hello")
    }

    func testTranscriptionFailureFallsBackWithError() async throws {
        let transport = StreamingFakeTransport()
        transport.commitInbox = [Self.committed("item-1"), Self.failed("unintelligible", itemID: "item-1")]
        let session = OpenAIRealtimeSession(
            transport: transport, model: "m", vocabulary: nil, language: nil,
            encoder: RealtimePCMEncoder(inputRate: 24_000, outputRate: 24_000))
        try await session.begin()

        do {
            _ = try await session.finish()
            XCTFail("expected transcription failure")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("unintelligible"))
        }
    }

    func testConnectionLossWhileFinishingThrows() async throws {
        let transport = FakeTransport()
        transport.disconnectAfterInbox = true
        let session = OpenAIRealtimeSession(
            transport: transport, model: "m", vocabulary: nil, language: nil,
            encoder: RealtimePCMEncoder(inputRate: 24_000, outputRate: 24_000),
            finishTimeout: .seconds(1))
        try await session.begin()

        do {
            _ = try await session.finish()
            XCTFail("expected connection loss")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("connection lost"))
        }
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
