import AVFoundation
import Foundation

/// Local transcription engine: decodes the recorded m4a back to 16kHz mono
/// Float32 and hands it to the LocalASRBackend (FluidAudio/Parakeet).
/// Dictionary terms are NOT biasable locally — they're enforced at cleanup (spec §6).
struct ParakeetEngine: TranscriptionEngine {
    let backend: LocalASRBackend

    func transcribe(_ audio: RecordedAudio, dictionaryTerms: [String]) async throws -> Transcript {
        try await backend.loadIfNeeded()
        let samples = try Self.decodeSamples(from: audio.fileURL)
        let text = try await backend.transcribe(samples)
        return Transcript(text: text, engineID: "parakeet")
    }

    /// Decodes any AVAudioFile-readable file to 16kHz mono Float32.
    static func decodeSamples(from url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        guard let readFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                             sampleRate: file.processingFormat.sampleRate,
                                             channels: 1, interleaved: false) else {
            throw AudioError.engineFailure("decode format")
        }
        let sink = AudioSink() // reuse the Phase-1 resampler: anything → 16kHz mono
        let chunkFrames: AVAudioFrameCount = 16_384
        // Guard on framePosition: read(into:) throws eofErr (-39) when asked to
        // read past EOF on current macOS instead of returning an empty buffer.
        while file.framePosition < file.length {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: readFormat, frameCapacity: chunkFrames) else {
                throw AudioError.engineFailure("decode buffer")
            }
            try file.read(into: buffer, frameCount: chunkFrames)
            if buffer.frameLength == 0 { break }
            try sink.append(buffer)
        }
        sink.finish()
        return sink.drainSamples()
    }
}
