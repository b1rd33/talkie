import Foundation

enum OpenAISSEEvent: Equatable {
    case delta(String)
    case done(text: String, detectedLanguages: [String])
}

struct OpenAISSEParser {
    private var buffer = Data()

    mutating func append(_ data: Data) throws -> [OpenAISSEEvent] {
        buffer.append(data)
        var events: [OpenAISSEEvent] = []
        let lineFeedDelimiter = Data("\n\n".utf8)
        let carriageReturnDelimiter = Data("\r\n\r\n".utf8)

        while let range = [
            buffer.range(of: lineFeedDelimiter),
            buffer.range(of: carriageReturnDelimiter),
        ].compactMap({ $0 }).min(by: { $0.lowerBound < $1.lowerBound }) {
            let frame = buffer[..<range.lowerBound]
            buffer.removeSubrange(..<range.upperBound)
            guard let line = String(data: frame, encoding: .utf8)?
                .split(separator: "\n")
                .first(where: { $0.hasPrefix("data: ") }) else {
                continue
            }
            let json = Data(line.dropFirst(6).utf8)
            guard let object = try JSONSerialization.jsonObject(with: json)
                as? [String: Any] else {
                throw EngineError.invalidResponse
            }

            switch object["type"] as? String {
            case "transcript.text.delta":
                events.append(.delta(object["delta"] as? String ?? ""))
            case "transcript.text.done":
                guard let text = object["text"] as? String else {
                    throw EngineError.invalidResponse
                }
                let languages = (object["languages"] as? [[String: Any]])?
                    .compactMap { $0["code"] as? String } ?? []
                events.append(
                    .done(text: text, detectedLanguages: languages))
            default:
                continue
            }
        }

        return events
    }
}
