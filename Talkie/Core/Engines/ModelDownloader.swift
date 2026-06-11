import Foundation
import Observation

/// Drives the local-model download with UI-observable state.
/// The actual fetch is injected: production uses FluidAudio's downloader
/// (mirror Fluidscribe's model-download call) targeting FluidAudioBackend.modelsDirectory.
@MainActor
@Observable
final class ModelDownloader {
    enum State: Equatable {
        case idle, downloading, ready
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var progress: Double = 0

    /// fetch(progressCallback) downloads everything; callback reports 0...1.
    private let fetch: (@escaping @Sendable (Double) -> Void) async throws -> Void

    init(fetch: @escaping (@escaping @Sendable (Double) -> Void) async throws -> Void) {
        self.fetch = fetch
    }

    func download() async {
        guard state != .downloading, state != .ready else { return }
        state = .downloading
        progress = 0
        do {
            try await fetch { [weak self] value in
                Task { @MainActor in self?.progress = value }
            }
            progress = 1.0
            state = .ready
        } catch {
            state = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// Settings' "Remove models" button (Task 5): back to square one after the files are deleted.
    func reset() {
        state = .idle
        progress = 0
    }
}
