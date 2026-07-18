import Foundation

struct VoiceActionResult: Equatable, Sendable {
    let text: String
    let pressEnter: Bool
}

enum VoiceActionProcessor {
    static func process(_ input: String, allowPressEnter: Bool) -> VoiceActionResult {
        var text = input
        var shouldPressEnter = false

        if allowPressEnter,
           let suffix = text.range(of: #"(?i)(?:\s+|^)press\s+enter[.!?]?\s*$"#,
                                   options: .regularExpression) {
            text.removeSubrange(suffix)
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            shouldPressEnter = true
        }

        text = replacePhrase("new paragraph", in: text, with: "\n\n")
        text = replacePhrase("new line", in: text, with: "\n")

        return VoiceActionResult(text: text, pressEnter: shouldPressEnter)
    }

    private static func replacePhrase(_ phrase: String, in input: String,
                                      with replacement: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: phrase)
        guard let expression = try? NSRegularExpression(
            pattern: #"(?i)(?<![\p{L}\p{N}_])"# + escaped + #"(?![\p{L}\p{N}_])"#)
        else { return input }

        let range = NSRange(input.startIndex..., in: input)
        let replaced = expression.stringByReplacingMatches(
            in: input, range: range, withTemplate: replacement)

        // Spoken actions usually arrive surrounded by spaces. Remove only the
        // horizontal whitespace adjacent to generated line breaks, preserving all
        // other dictated whitespace verbatim.
        return replaced
            .replacingOccurrences(of: #"[\t ]*\n[\t ]*"#,
                                  with: "\n", options: .regularExpression)
    }
}
