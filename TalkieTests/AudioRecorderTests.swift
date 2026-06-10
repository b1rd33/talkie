import XCTest
import AVFoundation
@testable import Talkie

final class AudioRecorderTests: XCTestCase {
    /// 0.5s of 440Hz sine at 48kHz stereo — simulates a hardware-format tap buffer.
    private func makeBuffer(sampleRate: Double = 48_000, channels: AVAudioChannelCount = 2,
                            seconds: Double = 0.5) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)!
        let frames = AVAudioFrameCount(sampleRate * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for ch in 0..<Int(channels) {
            let ptr = buffer.floatChannelData![ch]
            for i in 0..<Int(frames) {
                ptr[i] = sinf(2 * .pi * 440 * Float(i) / Float(sampleRate)) * 0.5
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
}
