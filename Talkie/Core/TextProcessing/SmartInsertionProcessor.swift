import Foundation

enum SmartInsertionProcessor {
    static func format(_ input: String, precedingText: String?) -> String {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let precedingText else { return text }

        let last = precedingText.last
        let trimmedPreceding = precedingText.trimmingCharacters(in: .whitespacesAndNewlines)
        let sentenceBoundary = trimmedPreceding.last
        let beginsSentence = trimmedPreceding.isEmpty
            || sentenceBoundary.map { ".!?\n".contains($0) } == true
        if beginsSentence, let first = text.first, first.isLetter {
            text.replaceSubrange(text.startIndex...text.startIndex,
                                 with: String(first).uppercased())
        }
        if let last, !last.isWhitespace, !last.isNewline,
           let first = text.first, first.isLetter || first.isNumber {
            text = " " + text
        }
        return text
    }
}
