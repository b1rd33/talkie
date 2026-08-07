import AVFoundation
import Observation

struct AudioSignalMetrics: Sendable, Equatable {
    let frameCount: Int
    let duration: TimeInterval
    let rms: Float
    let peak: Float
    let clippingRatio: Float
    let voicedDuration: TimeInterval
    let silentWindowRatio: Float

    static let unavailable = AudioSignalMetrics(
        frameCount: 0, duration: 0, rms: 0, peak: 0, clippingRatio: 0,
        voicedDuration: 0, silentWindowRatio: 0)
}

enum AudioHealthDecision: String, Sendable, Equatable {
    case healthy
    case tooShort
    case noSignal
    case noVoice
    case clipped
    case deviceLost
}

struct AudioHealthPolicy: Sendable, Equatable {
    let minimumDuration: TimeInterval
    let signalFloorRMS: Float
    let voiceActivationRMS: Float
    let minimumVoicedDuration: TimeInterval
    let clippingAmplitude: Float
    let maximumClippingRatio: Float
    let analysisWindowFrames: Int

    static let standard = AudioHealthPolicy(
        minimumDuration: 0.25,
        signalFloorRMS: 0.0005,
        voiceActivationRMS: 0.002,
        minimumVoicedDuration: 0.10,
        clippingAmplitude: 0.98,
        maximumClippingRatio: 0.10,
        analysisWindowFrames: 320) // 20 ms at AudioSink's 16 kHz target rate

    func evaluate(_ metrics: AudioSignalMetrics, deviceWasLost: Bool = false) -> AudioHealthDecision {
        if deviceWasLost { return .deviceLost }
        if metrics.duration < minimumDuration { return .tooShort }
        if metrics.rms < signalFloorRMS { return .noSignal }
        if metrics.voicedDuration < minimumVoicedDuration { return .noVoice }
        if metrics.clippingRatio > maximumClippingRatio { return .clipped }
        return .healthy
    }
}

/// A bounded energy gate for deciding when Instant mode may open a provider
/// connection. This is intentionally not called VAD: it measures voice-like signal
/// energy and cannot distinguish the user from a television or another speaker.
struct RealtimePreflightPolicy: Sendable, Equatable {
    let voiceLikeRMS: Float
    let minimumVoiceLikeDuration: TimeInterval
    let maximumBufferedDuration: TimeInterval

    static let standard = RealtimePreflightPolicy(
        voiceLikeRMS: AudioHealthPolicy.standard.voiceActivationRMS,
        minimumVoiceLikeDuration: 0.08,
        maximumBufferedDuration: 2.0)

    static let immediate = RealtimePreflightPolicy(
        voiceLikeRMS: 0, minimumVoiceLikeDuration: 0, maximumBufferedDuration: 0)
}

struct RealtimeSignalPreflight {
    private(set) var bufferedChunks: [[Float]] = []
    private(set) var bufferedFrameCount = 0
    private var voiceLikeFrameCount = 0
    private let policy: RealtimePreflightPolicy

    init(policy: RealtimePreflightPolicy = .standard) {
        self.policy = policy
    }

    mutating func append(_ chunk: [Float]) -> Bool {
        guard !chunk.isEmpty else { return isReady }
        bufferedChunks.append(chunk)
        bufferedFrameCount += chunk.count
        let energy = chunk.reduce(into: Double(0)) { sum, sample in
            sum += Double(sample) * Double(sample)
        }
        let rms = Float(sqrt(energy / Double(chunk.count)))
        if rms >= policy.voiceLikeRMS { voiceLikeFrameCount += chunk.count }

        let maximumFrames = Int(policy.maximumBufferedDuration * 16_000)
        while bufferedFrameCount > maximumFrames,
              bufferedChunks.count > 1 {
            bufferedFrameCount -= bufferedChunks.removeFirst().count
        }
        return isReady
    }

    var isReady: Bool {
        policy.minimumVoiceLikeDuration == 0
            || Double(voiceLikeFrameCount) / 16_000 >= policy.minimumVoiceLikeDuration
    }

    mutating func drainBufferedChunks() -> [[Float]] {
        defer {
            bufferedChunks.removeAll(keepingCapacity: false)
            bufferedFrameCount = 0
        }
        return bufferedChunks
    }
}

struct RecordedAudio: Sendable {
    let fileURL: URL
    let duration: TimeInterval
    let metrics: AudioSignalMetrics
    let healthDecision: AudioHealthDecision
    let requestedDeviceUID: String?
    let actualDeviceUID: String?

    init(fileURL: URL, duration: TimeInterval,
         metrics: AudioSignalMetrics = .unavailable,
         healthDecision: AudioHealthDecision = .healthy,
         requestedDeviceUID: String? = nil,
         actualDeviceUID: String? = nil) {
        self.fileURL = fileURL
        self.duration = duration
        self.metrics = metrics
        self.healthDecision = healthDecision
        self.requestedDeviceUID = requestedDeviceUID
        self.actualDeviceUID = actualDeviceUID
    }

    func validateHealth() throws {
        switch healthDecision {
        case .healthy, .clipped:
            return // clipping is usable audio; UI/diagnostics can surface it as a warning later
        case .tooShort: throw AudioError.recordingTooShort
        case .noSignal: throw AudioError.noSignal
        case .noVoice: throw AudioError.noVoice
        case .deviceLost: throw AudioError.deviceLost
        }
    }
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
    case recordingTooShort
    case noSignal
    case noVoice
    case deviceLost

    var errorDescription: String? {
        switch self {
        case .microphoneDenied: "Microphone access denied — enable it in System Settings."
        case .engineFailure(let detail): "Audio engine failed: \(detail)"
        case .nothingRecorded: "No audio was captured."
        case .recordingTooShort: "The recording was too short. Hold the dictation key a little longer."
        case .noSignal: "No microphone signal was detected. Check the selected input and its gain."
        case .noVoice: "No voice was detected. Try speaking closer to the microphone."
        case .deviceLost: "The microphone disconnected while recording. Reconnect it or choose another input."
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
    private let levelLock = NSLock()
    private var _latestLevel: Float = 0
    private let healthPolicy: AudioHealthPolicy
    private var energySum: Double = 0
    private var peakAmplitude: Float = 0
    private var clippedFrames = 0
    private var completedWindowFrames = 0
    private var completedSilentWindows = 0
    private var completedWindows = 0
    private var currentWindowEnergy: Double = 0
    private var currentWindowFrames = 0

    init(healthPolicy: AudioHealthPolicy = .standard) {
        self.healthPolicy = healthPolicy
    }
    /// Thread-safe: written on the audio tap thread, read on the main thread by the
    /// waveform timer (~30 Hz). Guarded so the cross-thread read isn't a data race.
    var latestLevel: Float {
        levelLock.lock(); defer { levelLock.unlock() }; return _latestLevel
    }
    private func setLevel(_ value: Float) {
        levelLock.lock(); _latestLevel = value; levelLock.unlock()
    }

    /// Streaming hook: every converted 16kHz mono chunk is forwarded here as it
    /// arrives (used by Instant mode). Called on the tap thread — consumer must
    /// be thread-safe. Accumulation into `samples` continues regardless, so the
    /// batch path always has the full recording for fallback.
    var chunkConsumer: (([Float]) -> Void)?

    var sampleCount: Int { samples.count }
    var duration: TimeInterval { Double(samples.count) / 16_000 }

    var metrics: AudioSignalMetrics {
        let count = samples.count
        guard count > 0 else { return .unavailable }
        var voicedFrames = completedWindowFrames
        var silentWindows = completedSilentWindows
        var windows = completedWindows
        if currentWindowFrames > 0 {
            windows += 1
            let windowRMS = Float(sqrt(currentWindowEnergy / Double(currentWindowFrames)))
            if windowRMS >= healthPolicy.voiceActivationRMS {
                voicedFrames += currentWindowFrames
            } else {
                silentWindows += 1
            }
        }
        return AudioSignalMetrics(
            frameCount: count,
            duration: duration,
            rms: Float(sqrt(energySum / Double(count))),
            peak: peakAmplitude,
            clippingRatio: Float(clippedFrames) / Float(count),
            voicedDuration: Double(voicedFrames) / 16_000,
            silentWindowRatio: windows == 0 ? 0 : Float(silentWindows) / Float(windows))
    }

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
            appendConverted(UnsafeBufferPointer(start: ptr, count: n))
            if let chunkConsumer {
                chunkConsumer(Array(UnsafeBufferPointer(start: ptr, count: n)))
            }
            var sum: Float = 0
            for i in 0..<n { sum += ptr[i] * ptr[i] }
            setLevel(min(1, sqrt(sum / Float(n)) * 10)) // scaled RMS for UI bars (bumped 5→10 per user: more sensitive/reactive)
        } else {
            setLevel(0)
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
                appendConverted(UnsafeBufferPointer(start: ptr, count: n))
                if let chunkConsumer {
                    chunkConsumer(Array(UnsafeBufferPointer(start: ptr, count: n)))
                }
            }
            if status != .haveData || n == 0 { break }
        }
        self.converter = nil
        self.sourceFormat = nil
    }

    private func appendConverted(_ converted: UnsafeBufferPointer<Float>) {
        samples.append(contentsOf: converted)
        for sample in converted {
            let amplitude = abs(sample)
            let square = Double(sample) * Double(sample)
            energySum += square
            currentWindowEnergy += square
            peakAmplitude = max(peakAmplitude, amplitude)
            if amplitude >= healthPolicy.clippingAmplitude { clippedFrames += 1 }
            currentWindowFrames += 1
            if currentWindowFrames == healthPolicy.analysisWindowFrames {
                let windowRMS = Float(sqrt(currentWindowEnergy / Double(currentWindowFrames)))
                if windowRMS >= healthPolicy.voiceActivationRMS {
                    completedWindowFrames += currentWindowFrames
                } else {
                    completedSilentWindows += 1
                }
                completedWindows += 1
                currentWindowEnergy = 0
                currentWindowFrames = 0
            }
        }
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
    private let preferredDeviceUID: () -> String?
    private let deviceCatalog: any AudioDeviceCataloging
    private let deviceMonitor: any AudioDeviceMonitoring
    private let healthPolicy: AudioHealthPolicy
    private var sink: AudioSink
    private var deviceResolution: AudioDeviceResolution?
    private var captureRequestedDeviceUID: String?
    private var deviceWasLost = false
    private(set) var isRecording = false

    init(preferredDeviceUID: @escaping () -> String? = { nil },
         deviceCatalog: (any AudioDeviceCataloging)? = nil,
         deviceMonitor: (any AudioDeviceMonitoring)? = nil,
         healthPolicy: AudioHealthPolicy = .standard) {
        self.preferredDeviceUID = preferredDeviceUID
        self.deviceCatalog = deviceCatalog ?? SystemAudioDeviceCatalog()
        self.deviceMonitor = deviceMonitor ?? SystemAudioDeviceMonitor()
        self.healthPolicy = healthPolicy
        self.sink = AudioSink(healthPolicy: healthPolicy)
    }

    var latestLevel: Float { sink.latestLevel }

    /// Forwarded to the active sink for the duration of a recording (Instant mode).
    var chunkConsumer: (([Float]) -> Void)? {
        didSet { sink.chunkConsumer = chunkConsumer }
    }

    func start() async throws {
        guard !isRecording else { return }
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        guard granted else { throw AudioError.microphoneDenied }

        sink = AudioSink(healthPolicy: healthPolicy)
        sink.chunkConsumer = chunkConsumer
        deviceWasLost = false
        captureRequestedDeviceUID = preferredDeviceUID()
        deviceResolution = deviceCatalog.configure(engine, preferredUID: captureRequestedDeviceUID)
        if case .configurationFailed(_, let status) = deviceResolution {
            throw AudioError.engineFailure("could not select input device (CoreAudio \(status))")
        }
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
        let activeUID = deviceResolution?.actualDevice?.uid
        deviceMonitor.start { [weak self] devices in
            guard let self, self.isRecording,
                  AudioDeviceSelection.activeDeviceWasRemoved(
                    uid: activeUID, devices: devices) else { return }
            self.deviceWasLost = true
        }
    }

    func stop() async throws -> RecordedAudio {
        teardown()
        sink.finish()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("talkie-\(UUID().uuidString).m4a")
        let written = try sink.writeM4A(to: url)
        let metrics = sink.metrics
        return RecordedAudio(
            fileURL: written,
            duration: sink.duration,
            metrics: metrics,
            healthDecision: healthPolicy.evaluate(metrics, deviceWasLost: deviceWasLost),
            requestedDeviceUID: captureRequestedDeviceUID,
            actualDeviceUID: deviceResolution?.actualDevice?.uid)
    }

    func discard() {
        teardown()
    }

    private func teardown() {
        deviceMonitor.stop()
        guard isRecording else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
    }
}
