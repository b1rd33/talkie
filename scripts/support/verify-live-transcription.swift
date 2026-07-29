import AVFoundation
import Foundation

enum VerificationError: Error {
    case invalidArguments
    case audioConversion
    case connection
    case timeout
}

func pcm24kMono(from url: URL) throws -> Data {
    let file = try AVAudioFile(forReading: url)
    let sourceFormat = file.processingFormat
    guard let source = AVAudioPCMBuffer(
        pcmFormat: sourceFormat,
        frameCapacity: AVAudioFrameCount(file.length)),
        let destinationFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 24_000,
            channels: 1,
            interleaved: true),
        let converter = AVAudioConverter(from: sourceFormat, to: destinationFormat)
    else {
        throw VerificationError.audioConversion
    }

    try file.read(into: source)
    let estimatedFrames = AVAudioFrameCount(
        ceil(Double(source.frameLength) * 24_000 / sourceFormat.sampleRate)) + 4_096
    guard let destination = AVAudioPCMBuffer(
        pcmFormat: destinationFormat,
        frameCapacity: estimatedFrames)
    else {
        throw VerificationError.audioConversion
    }

    var suppliedInput = false
    var conversionError: NSError?
    let status = converter.convert(to: destination, error: &conversionError) { _, inputStatus in
        if suppliedInput {
            inputStatus.pointee = .endOfStream
            return nil
        }
        suppliedInput = true
        inputStatus.pointee = .haveData
        return source
    }
    guard conversionError == nil,
          status == .haveData || status == .endOfStream,
          destination.frameLength > 0,
          let samples = destination.int16ChannelData?[0]
    else {
        throw VerificationError.audioConversion
    }
    return Data(bytes: samples, count: Int(destination.frameLength) * MemoryLayout<Int16>.size)
}

func sendJSON(_ object: [String: Any], to task: URLSessionWebSocketTask) async throws {
    let data = try JSONSerialization.data(withJSONObject: object)
    try await task.send(.string(String(decoding: data, as: UTF8.self)))
}

func verifyRealtime(apiKey: String, audioURL: URL, model: String) async throws {
    let pcm = try pcm24kMono(from: audioURL)
    var request = URLRequest(
        url: URL(string: "wss://api.openai.com/v1/realtime?intent=transcription")!)
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

    let task = URLSession.shared.webSocketTask(with: request)
    task.resume()
    defer { task.cancel(with: .normalClosure, reason: nil) }

    try await sendJSON([
        "type": "session.update",
        "session": [
            "type": "transcription",
            "audio": [
                "input": [
                    "format": ["type": "audio/pcm", "rate": 24_000],
                    "transcription": [
                        "model": model,
                        "languages": ["en"],
                        "delay": "medium",
                    ],
                    "turn_detection": NSNull(),
                ],
            ],
        ],
    ], to: task)

    let chunkSize = 4_800
    var offset = 0
    while offset < pcm.count {
        let end = min(offset + chunkSize, pcm.count)
        try await sendJSON([
            "type": "input_audio_buffer.append",
            "audio": pcm[offset..<end].base64EncodedString(),
        ], to: task)
        offset = end
    }
    try await sendJSON([
        "type": "input_audio_buffer.commit",
        "event_id": "talkie-live-verification",
    ], to: task)

    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
            while true {
                let message = try await task.receive()
                let data: Data
                switch message {
                case .string(let text): data = Data(text.utf8)
                case .data(let received): data = received
                @unknown default: throw VerificationError.connection
                }
                guard let payload = try JSONSerialization.jsonObject(with: data)
                        as? [String: Any],
                      let type = payload["type"] as? String
                else { continue }
                if type == "error" {
                    throw VerificationError.connection
                }
                if type == "conversation.item.input_audio_transcription.completed",
                   let transcript = payload["transcript"] as? String,
                   !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return
                }
            }
        }
        group.addTask {
            try await Task.sleep(for: .seconds(20))
            throw VerificationError.timeout
        }
        _ = try await group.next()
        group.cancelAll()
    }
}

guard CommandLine.arguments.count == 3,
      let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
      !apiKey.isEmpty
else {
    throw VerificationError.invalidArguments
}

try await verifyRealtime(
    apiKey: apiKey,
    audioURL: URL(fileURLWithPath: CommandLine.arguments[1]),
    model: CommandLine.arguments[2])
print("Realtime live transcription verification passed.")
