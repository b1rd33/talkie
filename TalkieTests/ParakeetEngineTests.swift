import XCTest
import AVFoundation
@testable import Talkie

final class ParakeetEngineTests: XCTestCase {
    final class FakeBackend: LocalASRBackend, @unchecked Sendable {
        var loaded = 0
        var received: [Float] = []
        var result = "local transcript"
        func loadIfNeeded() async throws { loaded += 1 }
        func transcribe(_ samples: [Float]) async throws -> String {
            received = samples
            return result
        }
    }

    /// Writes a 0.5s 16kHz mono m4a fixture and returns its URL.
    private func makeAudioFixture() throws -> URL {
        let sink = AudioSink()
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8000)!
        buffer.frameLength = 8000
        for i in 0..<8000 { buffer.floatChannelData![0][i] = sinf(Float(i) * 0.1) * 0.4 }
        try sink.append(buffer)
        sink.finish()
        return try sink.writeM4A(to: FileManager.default.temporaryDirectory
            .appendingPathComponent("parakeet-test-\(UUID().uuidString).m4a"))
    }

    func testDecodesAudioAndReturnsBackendText() async throws {
        let backend = FakeBackend()
        let engine = ParakeetEngine(backend: backend)
        let url = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let transcript = try await engine.transcribe(
            RecordedAudio(fileURL: url, duration: 0.5), dictionaryTerms: ["ignored"])
        XCTAssertEqual(transcript.text, "local transcript")
        XCTAssertEqual(transcript.engineID, "parakeet")
        XCTAssertEqual(backend.loaded, 1)
        // ~0.5s of 16k audio decoded back out of the m4a (AAC adds priming ~few hundred frames)
        XCTAssertEqual(Double(backend.received.count), 8000, accuracy: 1600)
    }

    func testBackendErrorSurfaces() async throws {
        final class FailingBackend: LocalASRBackend, @unchecked Sendable {
            func loadIfNeeded() async throws { throw EngineError.requestFailed(status: 0, message: "no models") }
            func transcribe(_ samples: [Float]) async throws -> String { "" }
        }
        let engine = ParakeetEngine(backend: FailingBackend())
        let url = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            _ = try await engine.transcribe(RecordedAudio(fileURL: url, duration: 0.5), dictionaryTerms: [])
            XCTFail("expected throw")
        } catch let error as EngineError {
            guard case .requestFailed = error else { return XCTFail("wrong case") }
        } catch { XCTFail("wrong error: \(error)") }
    }
}
