import Foundation

/// The ONLY seam to the FluidAudio SDK. Exactly one production type conforms
/// (FluidAudioBackend); tests use fakes. Keeps the SDK import out of the rest
/// of the codebase and the router/engine logic fully unit-testable.
protocol LocalASRBackend: Sendable {
    /// Loads CoreML models into memory on first call; cheap no-op afterwards.
    func loadIfNeeded() async throws
    /// 16kHz mono Float32 samples in, final transcript out.
    func transcribe(_ samples: [Float]) async throws -> String
}
