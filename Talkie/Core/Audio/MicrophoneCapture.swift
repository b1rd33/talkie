import AVFoundation
import OSLog

/// Let AVFoundation negotiate Bluetooth input formats. Each delivered buffer
/// carries its actual PCM format; no cached AudioUnit bus format is imposed.
final class MicrophoneCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    // Session mutations and audio delivery are confined to their queues. stop() drains both.
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.archiev.talkie.capture")
    private let audioQueue = DispatchQueue(label: "com.archiev.talkie.capture.audio")
    private let sink: AudioSink
    private var deliveredFormat: AVAudioFormat?
    private static let logger = Logger(subsystem: "com.archiev.talkie", category: "capture")

    init(sink: AudioSink) { self.sink = sink }

    func start(deviceUID: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [self] in
                do {
                    guard let device = AVCaptureDevice(uniqueID: deviceUID) else {
                        throw AudioError.deviceLost
                    }
                    let input = try AVCaptureDeviceInput(device: device)
                    let output = AVCaptureAudioDataOutput()
                    output.setSampleBufferDelegate(self, queue: audioQueue)
                    session.beginConfiguration()
                    guard session.canAddInput(input) else {
                        session.commitConfiguration()
                        throw AudioError.engineFailure("could not open the selected microphone")
                    }
                    session.addInput(input)
                    guard session.canAddOutput(output) else {
                        session.commitConfiguration()
                        throw AudioError.engineFailure("could not read microphone audio")
                    }
                    session.addOutput(output)
                    session.commitConfiguration()
                    session.startRunning()
                    guard session.isRunning else {
                        throw AudioError.engineFailure("the microphone did not start")
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() {
        sessionQueue.sync { session.stopRunning() }
        // All callbacks must finish before AudioRecorder drains or discards its sink.
        audioQueue.sync {}
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        do {
            let buffer = try Self.pcmBuffer(from: sampleBuffer)
            if deliveredFormat != buffer.format {
                deliveredFormat = buffer.format
                Self.logger.notice("Microphone PCM: \(buffer.format.sampleRate, privacy: .public) Hz, \(buffer.format.channelCount, privacy: .public) channels")
            }
            sink.capture(buffer)
        }
        catch { sink.recordFailure(error) }
    }

    static func pcmBuffer(from sampleBuffer: CMSampleBuffer) throws -> AVAudioPCMBuffer {
        guard CMSampleBufferDataIsReady(sampleBuffer),
              let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let stream = CMAudioFormatDescriptionGetStreamBasicDescription(description),
              stream.pointee.mFormatID == kAudioFormatLinearPCM else {
            throw AudioError.engineFailure("the microphone delivered an invalid audio format")
        }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        let count = CMSampleBufferGetNumSamples(sampleBuffer)
        guard count > 0, count <= Int(Int32.max),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else {
            throw AudioError.engineFailure("the microphone delivered an empty audio buffer")
        }
        buffer.frameLength = AVAudioFrameCount(count)
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(count), into: buffer.mutableAudioBufferList)
        guard status == noErr else {
            throw AudioError.engineFailure("could not copy microphone audio (\(status))")
        }
        return buffer
    }
}
