import AVFoundation
import Observation

struct RecordedAudio: Sendable {
    let fileURL: URL
    let duration: TimeInterval
}

@MainActor
protocol AudioRecording: AnyObject {
    var latestLevel: Float { get }
    var chunkConsumer: (([Float]) -> Void)? { get set }
    func start() async throws
    func stop() async throws -> RecordedAudio
    func discard()
}

enum AudioError: Error, LocalizedError {
    case microphoneDenied
    case engineFailure(String)
    case nothingRecorded

    var errorDescription: String? {
        switch self {
        case .microphoneDenied: "Microphone access denied — enable it in System Settings."
        case .engineFailure(let detail): "Audio engine failed: \(detail)"
        case .nothingRecorded: "No audio was captured."
        }
    }
}

/// Accumulates tap buffers, resampling to 16kHz mono Float32. Pure — unit tested.
final class AudioSink {
    static let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                            sampleRate: 16_000, channels: 1, interleaved: false)!
    private var samples: [Float] = [] // ~77 MB at the 20-min session cap (16k × 4 bytes/s)
    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?
    private(set) var latestLevel: Float = 0

    /// Streaming hook: every converted 16kHz mono chunk is forwarded here as it
    /// arrives (used by Instant mode). Called on the tap thread — consumer must
    /// be thread-safe. Accumulation into `samples` continues regardless, so the
    /// batch path always has the full recording for fallback.
    var chunkConsumer: (([Float]) -> Void)?

    var sampleCount: Int { samples.count }
    var duration: TimeInterval { Double(samples.count) / 16_000 }

    /// Hands out the accumulated 16kHz mono samples (used by the local engine's decoder).
    func drainSamples() -> [Float] { samples }

    func append(_ buffer: AVAudioPCMBuffer) throws {
        if converter == nil || sourceFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: Self.targetFormat)
            sourceFormat = buffer.format
        }
        guard let converter else { throw AudioError.engineFailure("no converter") }

        let ratio = 16_000.0 / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: Self.targetFormat, frameCapacity: capacity) else {
            throw AudioError.engineFailure("no output buffer")
        }
        var fed = false
        var convError: NSError?
        converter.convert(to: out, error: &convError) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        if let convError { throw AudioError.engineFailure(convError.localizedDescription) }

        let n = Int(out.frameLength)
        if n > 0, let ptr = out.floatChannelData?[0] {
            samples.append(contentsOf: UnsafeBufferPointer(start: ptr, count: n))
            if let chunkConsumer {
                chunkConsumer(Array(UnsafeBufferPointer(start: ptr, count: n)))
            }
            var sum: Float = 0
            for i in 0..<n { sum += ptr[i] * ptr[i] }
            latestLevel = min(1, sqrt(sum / Float(n)) * 4) // scaled RMS for UI bars
        } else {
            latestLevel = 0
        }
    }

    /// Drains the resampler's internal filter tail. Call once when capture ends —
    /// without this the last ~70ms of speech stays inside the converter and is lost.
    func finish() {
        guard let converter else { return }
        while true {
            guard let out = AVAudioPCMBuffer(pcmFormat: Self.targetFormat, frameCapacity: 4096) else { break }
            var convError: NSError?
            let status = converter.convert(to: out, error: &convError) { _, outStatus in
                outStatus.pointee = .endOfStream
                return nil
            }
            let n = Int(out.frameLength)
            if n > 0, let ptr = out.floatChannelData?[0] {
                samples.append(contentsOf: UnsafeBufferPointer(start: ptr, count: n))
                if let chunkConsumer {
                    chunkConsumer(Array(UnsafeBufferPointer(start: ptr, count: n)))
                }
            }
            if status != .haveData || n == 0 { break }
        }
        self.converter = nil
        self.sourceFormat = nil
    }

    func writeM4A(to url: URL) throws -> URL {
        guard !samples.isEmpty else { throw AudioError.nothingRecorded }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        let chunk = 16_384
        var index = 0
        while index < samples.count {
            let count = min(chunk, samples.count - index)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: Self.targetFormat,
                                                frameCapacity: AVAudioFrameCount(count)) else {
                throw AudioError.engineFailure("could not allocate write buffer")
            }
            buffer.frameLength = AVAudioFrameCount(count)
            samples.withUnsafeBufferPointer { src in
                buffer.floatChannelData![0].update(from: src.baseAddress! + index, count: count)
            }
            try file.write(from: buffer)
            index += count
        }
        return url
    }
}

/// Live microphone recorder. Thin shell over AudioSink — manually verified.
@MainActor
@Observable
final class AudioRecorder: AudioRecording {
    private let engine = AVAudioEngine()
    private var sink = AudioSink()
    private(set) var isRecording = false

    var latestLevel: Float { sink.latestLevel }

    /// Forwarded to the active sink for the duration of a recording (Instant mode).
    var chunkConsumer: (([Float]) -> Void)? {
        didSet { sink.chunkConsumer = chunkConsumer }
    }

    func start() async throws {
        guard !isRecording else { return }
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        guard granted else { throw AudioError.microphoneDenied }

        sink = AudioSink()
        sink.chunkConsumer = chunkConsumer
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { throw AudioError.engineFailure("no input device") }
        let sink = self.sink
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            try? sink.append(buffer)
        }
        engine.prepare()
        do { try engine.start() } catch {
            input.removeTap(onBus: 0)
            throw AudioError.engineFailure(error.localizedDescription)
        }
        isRecording = true
    }

    func stop() async throws -> RecordedAudio {
        teardown()
        sink.finish()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("talkie-\(UUID().uuidString).m4a")
        let written = try sink.writeM4A(to: url)
        return RecordedAudio(fileURL: written, duration: sink.duration)
    }

    func discard() {
        teardown()
    }

    private func teardown() {
        guard isRecording else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
    }
}
