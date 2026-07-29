import Foundation

struct TranscriptionContext: Sendable, Equatable {
    let prompt: String?
    let keywords: [String]
    let languages: [String]

    var legacyLanguage: String? { languages.first }

    static func build(
        prompt: String,
        dictionaryTerms: [String],
        languageCodes: [String]
    ) -> Self {
        let normalizedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)

        var seenKeywords = Set<String>()
        let keywords = dictionaryTerms.compactMap { value -> String? in
            let singleLine = value
                .replacingOccurrences(of: "\r", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            guard !singleLine.isEmpty,
                  !singleLine.contains("<"),
                  !singleLine.contains(">") else { return nil }
            let key = singleLine.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current)
            guard seenKeywords.insert(key).inserted else { return nil }
            return singleLine
        }

        var seenLanguages = Set<String>()
        let languages = languageCodes
            .compactMap(SupportedLanguages.openAITranscriptionCode)
            .filter { seenLanguages.insert($0).inserted }

        return Self(
            prompt: normalizedPrompt.isEmpty ? nil : normalizedPrompt,
            keywords: keywords,
            languages: languages)
    }
}
