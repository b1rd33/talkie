import Foundation

struct SnippetExpansion: Equatable, Sendable {
    let trigger: String
    let expansion: String
}

struct ProtectedSnippetText: Equatable, Sendable {
    let text: String
    fileprivate let replacements: [String: String]

    func restore(_ processedText: String) -> String {
        replacements.reduce(processedText) { result, replacement in
            result.replacingOccurrences(of: replacement.key, with: replacement.value)
        }
    }
}

enum SnippetProcessor {
    static func normalize(_ trigger: String) -> String {
        trigger.split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }

    static func protect(_ input: String, snippets: [SnippetExpansion]) -> ProtectedSnippetText {
        var text = input
        var replacements: [String: String] = [:]
        // Longest trigger wins when one trigger contains another.
        let ordered = snippets.sorted {
            normalize($0.trigger).count > normalize($1.trigger).count
        }
        var tokenIndex = 0
        for snippet in ordered {
            let components = normalize(snippet.trigger).split(separator: " ")
            guard !components.isEmpty else { continue }
            let phrase = components.map { NSRegularExpression.escapedPattern(for: String($0)) }
                .joined(separator: #"\s+"#)
            let pattern = #"(?<![\p{L}\p{N}_])"# + phrase + #"(?![\p{L}\p{N}_])"#
            guard let regex = try? NSRegularExpression(pattern: pattern,
                                                       options: [.caseInsensitive]) else { continue }
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches.reversed() {
                guard let range = Range(match.range, in: text) else { continue }
                let token = "__TALKIE_SNIPPET_\(tokenIndex)_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))__"
                replacements[token] = snippet.expansion
                text.replaceSubrange(range, with: token)
                tokenIndex += 1
            }
        }
        return ProtectedSnippetText(text: text, replacements: replacements)
    }
}
