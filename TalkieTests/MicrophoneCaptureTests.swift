import AVFoundation
import XCTest
@testable import Talkie

final class MicrophoneCaptureTests: XCTestCase {
    func testCapturePreservesActualPCMFormatAndSamplesAcrossBluetoothRates() throws {
        let sink = AudioSink()
        for rate in [24_000.0, 48_000.0] {
            let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16,
                                                     sampleRate: rate, channels: 1, interleaved: true))
            let count = Int(rate / 2)
            let original = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format,
                                                         frameCapacity: AVAudioFrameCount(count)))
            original.frameLength = AVAudioFrameCount(count)
            let samples = try XCTUnwrap(original.int16ChannelData?[0])
            for i in 0..<count {
                samples[i] = Int16(sin(Double(i) * 2 * .pi * 440 / rate) * 12_000)
            }
            var sampleBuffer: CMSampleBuffer?
            XCTAssertEqual(CMAudioSampleBufferCreateWithPacketDescriptions(
                allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: false,
                makeDataReadyCallback: nil, refcon: nil,
                formatDescription: format.formatDescription, sampleCount: count,
                presentationTimeStamp: .zero, packetDescriptions: nil,
                sampleBufferOut: &sampleBuffer), noErr)
            let captured = try XCTUnwrap(sampleBuffer)
            XCTAssertEqual(CMSampleBufferSetDataBufferFromAudioBufferList(
                captured, blockBufferAllocator: kCFAllocatorDefault,
                blockBufferMemoryAllocator: kCFAllocatorDefault, flags: 0,
                bufferList: original.audioBufferList), noErr)
            XCTAssertEqual(CMSampleBufferSetDataReady(captured), noErr)
            let copied = try MicrophoneCapture.pcmBuffer(from: captured)
            XCTAssertEqual(copied.format, format)
            XCTAssertEqual(copied.frameLength, original.frameLength)
            XCTAssertEqual(Array(UnsafeBufferPointer(start: copied.int16ChannelData![0], count: count)),
                           Array(UnsafeBufferPointer(start: samples, count: count)))
            sink.capture(copied)
        }
        sink.finish()
        try sink.validateCapture()
        XCTAssertEqual(sink.duration, 1, accuracy: 0.03)
        XCTAssertEqual(sink.metrics.rms, 12_000 / 32_768 / sqrt(2), accuracy: 0.01)
    }
}
