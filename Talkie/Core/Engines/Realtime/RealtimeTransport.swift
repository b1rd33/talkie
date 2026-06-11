import Foundation

/// Seam over the WebSocket so session logic is testable without a network.
protocol RealtimeTransport: Sendable {
    func connect() async throws
    func send(_ data: Data) async throws
    func receive() async throws -> Data
    func close()
}

/// URLSessionWebSocketTask-backed production transport.
/// ⚠️ Endpoint reconciled against OpenAI's current Realtime docs (2026-06):
/// transcription-intent sessions connect via ?intent=transcription.
final class OpenAIRealtimeTransport: RealtimeTransport, @unchecked Sendable {
    private let apiKey: String
    private var task: URLSessionWebSocketTask?

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func connect() async throws {
        var request = URLRequest(url: URL(string: "wss://api.openai.com/v1/realtime?intent=transcription")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let task = URLSession.shared.webSocketTask(with: request)
        self.task = task
        task.resume()
    }

    func send(_ data: Data) async throws {
        guard let task else { throw EngineError.invalidResponse }
        try await task.send(.string(String(decoding: data, as: UTF8.self)))
    }

    func receive() async throws -> Data {
        guard let task else { throw EngineError.invalidResponse }
        switch try await task.receive() {
        case .string(let text): return Data(text.utf8)
        case .data(let data): return data
        @unknown default: throw EngineError.invalidResponse
        }
    }

    func close() {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }
}
