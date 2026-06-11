import AVFoundation
import Foundation

/// Converts the pipeline's 16kHz mono Float32 chunks into the Realtime API's
/// wire format: pcm16 little-endian mono (24kHz unless docs reconcile otherwise).
/// Stateful (owns an AVAudioConverter) — one instance per live session.
final class RealtimePCMEncoder {
    private let inputFormat: AVAudioFormat
    private let outputRate: Double
    private var converter: AVAudioConverter?

    init(inputRate: Double = 16_000, outputRate: Double = 24_000) {
        self.inputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: inputRate, channels: 1, interleaved: false)!
        self.outputRate = outputRate
    }

    func encode(_ samples: [Float]) throws -> Data {
        guard !samples.isEmpty else { return Data() }
        if inputFormat.sampleRate == outputRate {
            return Self.pcm16(samples)
        }
        let resampled = try resample(samples, endOfStream: false)
        return Self.pcm16(resampled)
    }

    /// Drains the resampler's filter tail — call once when the session ends.
    func flush() throws -> Data {
        guard inputFormat.sampleRate != outputRate, converter != nil else { return Data() }
        let tail = try resample([], endOfStream: true)
        converter = nil
        return Self.pcm16(tail)
    }

    private func resample(_ samples: [Float], endOfStream: Bool) throws -> [Float] {
        let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                      sampleRate: outputRate, channels: 1, interleaved: false)!
        if converter == nil { converter = AVAudioConverter(from: inputFormat, to: outFormat) }
        guard let converter else { throw AudioError.engineFailure("no realtime converter") }

        var inBuffer: AVAudioPCMBuffer?
        if !samples.isEmpty {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: inputFormat,
                                                frameCapacity: AVAudioFrameCount(samples.count)) else {
                throw AudioError.engineFailure("realtime input buffer")
            }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { src in
                buffer.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
            }
            inBuffer = buffer
        }

        var out: [Float] = []
        var fed = false
        while true {
            let capacity = AVAudioFrameCount(max(1024, Double(samples.count) * outputRate / inputFormat.sampleRate + 64))
            guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else {
                throw AudioError.engineFailure("realtime output buffer")
            }
            var convError: NSError?
            let status = converter.convert(to: outBuffer, error: &convError) { _, outStatus in
                if endOfStream { outStatus.pointee = .endOfStream; return nil }
                if fed { outStatus.pointee = .noDataNow; return nil }
                fed = true
                outStatus.pointee = .haveData
                return inBuffer
            }
            if let convError { throw AudioError.engineFailure(convError.localizedDescription) }
            let n = Int(outBuffer.frameLength)
            if n > 0, let ptr = outBuffer.floatChannelData?[0] {
                out.append(contentsOf: UnsafeBufferPointer(start: ptr, count: n))
            }
            if !endOfStream || status != .haveData || n == 0 { break }
        }
        return out
    }

    private static func pcm16(_ samples: [Float]) -> Data {
        var data = Data(capacity: samples.count * 2)
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            var value = Int16(clamped * Float(Int16.max)).littleEndian
            withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
        }
        return data
    }
}
