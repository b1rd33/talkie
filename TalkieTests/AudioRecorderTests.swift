import XCTest
import AVFoundation
@testable import Talkie

final class AudioRecorderTests: XCTestCase {
    /// 0.5s of 440Hz sine at 48kHz stereo — simulates a hardware-format tap buffer.
    private func makeBuffer(sampleRate: Double = 48_000, channels: AVAudioChannelCount = 2,
                            seconds: Double = 0.5, amplitude: Float = 0.5) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)!
        let frames = AVAudioFrameCount(sampleRate * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for ch in 0..<Int(channels) {
            let ptr = buffer.floatChannelData![ch]
            for i in 0..<Int(frames) {
                ptr[i] = sinf(2 * .pi * 440 * Float(i) / Float(sampleRate)) * amplitude
            }
        }
        return buffer
    }

    func testAccumulatesAndResamplesTo16k() throws {
        let sink = AudioSink()
        try sink.append(makeBuffer()) // 0.5s @ 48k stereo
        sink.finish() // drain the resampler tail, exactly as stop() does
        // ~0.5s at 16kHz mono = ~8000 samples (resampler may differ by a few frames)
        XCTAssertEqual(Double(sink.sampleCount), 8_000, accuracy: 200)
    }

    func testLevelReflectsLoudness() throws {
        let loudSink = AudioSink()
        try loudSink.append(makeBuffer())
        XCTAssertGreaterThan(loudSink.latestLevel, 0.05)
        // Fresh sink: a stateful resampler rings residual signal into the next
        // buffer, so silence-after-sine is not a fair "quiet" probe.
        let quietSink = AudioSink()
        let quiet = AVAudioPCMBuffer(pcmFormat: makeBuffer().format, frameCapacity: 4800)!
        quiet.frameLength = 4800 // silence (zero-filled)
        try quietSink.append(quiet)
        XCTAssertLessThan(quietSink.latestLevel, 0.01)
    }

    func testChunkConsumerReceivesConvertedChunks() throws {
        let sink = AudioSink()
        var received: [[Float]] = []
        sink.chunkConsumer = { received.append($0) }
        try sink.append(makeBuffer()) // 0.5s @ 48k stereo → ~8000 samples @ 16k mono
        sink.finish()
        let total = received.reduce(0) { $0 + $1.count }
        XCTAssertEqual(Double(total), Double(sink.sampleCount), accuracy: 1)
        XCTAssertFalse(received.isEmpty)
    }

    func testWritesPlayableM4A() throws {
        let sink = AudioSink()
        try sink.append(makeBuffer(seconds: 1.0))
        let url = try sink.writeM4A(to: FileManager.default.temporaryDirectory
            .appendingPathComponent("talkie-test-\(UUID().uuidString).m4a"))
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try AVAudioFile(forReading: url)
        let duration = Double(file.length) / file.fileFormat.sampleRate
        XCTAssertEqual(duration, 1.0, accuracy: 0.2)
    }

    func testMetricsAreAccumulatedFromConvertedSamples() throws {
        let sink = AudioSink()
        try sink.append(makeBuffer(seconds: 0.5, amplitude: 0.5))
        sink.finish()

        let metrics = sink.metrics
        XCTAssertEqual(metrics.frameCount, sink.sampleCount)
        XCTAssertEqual(metrics.duration, 0.5, accuracy: 0.02)
        XCTAssertEqual(metrics.rms, 0.5 / sqrt(2), accuracy: 0.03)
        XCTAssertEqual(metrics.peak, 0.5, accuracy: 0.03)
        XCTAssertEqual(metrics.clippingRatio, 0, accuracy: 0.001)
        XCTAssertGreaterThan(metrics.voicedDuration, 0.45)
        XCTAssertLessThan(metrics.silentWindowRatio, 0.05)
    }

    func testMetricsClassifyGeneratedSilence() throws {
        let sink = AudioSink()
        try sink.append(makeBuffer(seconds: 0.5, amplitude: 0))
        sink.finish()

        XCTAssertEqual(sink.metrics.rms, 0, accuracy: 0.000_001)
        XCTAssertEqual(sink.metrics.voicedDuration, 0, accuracy: 0.001)
        XCTAssertGreaterThan(sink.metrics.silentWindowRatio, 0.95)
        XCTAssertEqual(AudioHealthPolicy.standard.evaluate(sink.metrics), .noSignal)
    }

    func testPolicyDistinguishesTooShortNoSignalNoVoiceClippingAndDeviceLoss() {
        let policy = AudioHealthPolicy.standard
        func metrics(duration: TimeInterval = 1, rms: Float = 0.05,
                     clipping: Float = 0, voiced: TimeInterval = 0.5) -> AudioSignalMetrics {
            AudioSignalMetrics(frameCount: Int(duration * 16_000), duration: duration,
                               rms: rms, peak: 0.5, clippingRatio: clipping,
                               voicedDuration: voiced, silentWindowRatio: 0.5)
        }

        XCTAssertEqual(policy.evaluate(metrics(duration: 0.1)), .tooShort)
        XCTAssertEqual(policy.evaluate(metrics(rms: 0, voiced: 0)), .noSignal)
        XCTAssertEqual(policy.evaluate(metrics(rms: 0.002, voiced: 0)), .noVoice)
        XCTAssertEqual(policy.evaluate(metrics(clipping: 0.2)), .clipped)
        XCTAssertEqual(policy.evaluate(metrics()), .healthy)
        XCTAssertEqual(policy.evaluate(metrics(), deviceWasLost: true), .deviceLost)
    }

    func testRecordedAudioHealthValidationIsBackwardsCompatible() throws {
        let legacy = RecordedAudio(fileURL: URL(fileURLWithPath: "/tmp/legacy.m4a"), duration: 1)
        XCTAssertNoThrow(try legacy.validateHealth())

        let unhealthy = RecordedAudio(
            fileURL: URL(fileURLWithPath: "/tmp/silent.m4a"), duration: 1,
            healthDecision: .noSignal)
        XCTAssertThrowsError(try unhealthy.validateHealth()) { error in
            guard case AudioError.noSignal = error else {
                return XCTFail("Expected noSignal, got \(error)")
            }
        }
    }

    func testRealtimePreflightDoesNotOpenForSilenceAndBoundsItsBuffer() {
        let policy = RealtimePreflightPolicy(
            voiceLikeRMS: 0.01, minimumVoiceLikeDuration: 0.1,
            maximumBufferedDuration: 0.2)
        var preflight = RealtimeSignalPreflight(policy: policy)

        for _ in 0..<20 {
            XCTAssertFalse(preflight.append(Array(repeating: 0, count: 320)))
        }

        XCTAssertLessThanOrEqual(preflight.bufferedFrameCount, 3_200)
    }

    func testRealtimePreflightPreservesBufferedChunkOrderWhenGateOpens() {
        let policy = RealtimePreflightPolicy(
            voiceLikeRMS: 0.01, minimumVoiceLikeDuration: 0.02,
            maximumBufferedDuration: 1)
        var preflight = RealtimeSignalPreflight(policy: policy)
        let silence = Array(repeating: Float(0), count: 160)
        let voiceLike = Array(repeating: Float(0.05), count: 320)

        XCTAssertFalse(preflight.append(silence))
        XCTAssertTrue(preflight.append(voiceLike))
        XCTAssertEqual(preflight.drainBufferedChunks(), [silence, voiceLike])
        XCTAssertEqual(preflight.bufferedFrameCount, 0)
    }
}
