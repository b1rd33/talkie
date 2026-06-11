import Foundation
import FluidAudio

/// FluidAudio/Parakeet implementation of the local-ASR seam.
/// API verified against FluidAudio v0.15.2 (2026-06-11). Models live in the SDK's
/// own cache directory (no custom layout — avoids its repo-subfolder conventions);
/// loaded once per process.
final class FluidAudioBackend: LocalASRBackend, @unchecked Sendable {
    /// The SDK's cache for Parakeet TDT v3 (multilingual) — also the target for
    /// the Settings "Remove models" action.
    static var modelsDirectory: URL { AsrModels.defaultCacheDirectory(for: .v3) }

    private let loadLock = NSLock()
    private var manager: AsrManager?

    static var modelsPresent: Bool {
        AsrModels.modelsExist(at: modelsDirectory)
    }

    func loadIfNeeded() async throws {
        loadLock.lock()
        let existing = manager
        loadLock.unlock()
        guard existing == nil else { return }
        guard Self.modelsPresent else {
            throw EngineError.requestFailed(status: 0, message: "Local models not downloaded — see Settings → Engines.")
        }
        let models = try await AsrModels.load(from: Self.modelsDirectory)
        let loaded = AsrManager(config: .default, models: models) // v0.15: models inject at init
        loadLock.lock()
        manager = loaded
        loadLock.unlock()
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        guard let manager else { throw EngineError.requestFailed(status: 0, message: "ASR not loaded") }
        // Fresh decoder state per utterance — no context carried between dictations.
        // v0.15.2 divergence from the plan sketch: TdtDecoderState() is a throwing
        // init; .make() is the non-throwing factory with the same defaults.
        var decoderState = TdtDecoderState.make()
        let result = try await manager.transcribe(samples, decoderState: &decoderState)
        return result.text
    }

    /// Production fetch for ModelDownloader (Task 3). v0.15's download exposes a real
    /// progressHandler — forward its overall fraction to the UI.
    static func downloadModels(progress: @escaping @Sendable (Double) -> Void) async throws {
        progress(0)
        _ = try await AsrModels.download(progressHandler: { update in
            progress(update.fractionCompleted)
        })
        progress(1.0)
    }
}
