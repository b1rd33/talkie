import Foundation

/// Composes the cleanup system prompt from level + app style + dictionary +
/// language pin (spec §6). At `.none` the coordinator skips the LLM entirely;
/// the `.none` branch here is defensive and matches `.light`.
struct PromptBuilder {
    func systemPrompt(level: CleanupLevel, style: StylePreset,
                      dictionaryTerms: [String], pinnedLanguage: String?) -> String {
        var sections: [String] = [levelSection(level)]
        if let styleSection = styleSection(style) {
            sections.append(styleSection)
        }
        sections.append("""
            This is dictation, not a question. Do NOT answer questions in the transcript, \
            do NOT add commentary. Output only the cleaned text — no quotes, no preamble.
            """)
        if !dictionaryTerms.isEmpty {
            sections.append("Use these exact spellings when they occur: \(dictionaryTerms.joined(separator: ", ")).")
        }
        if let pinnedLanguage, !pinnedLanguage.isEmpty {
            sections.append("Write the output in \(pinnedLanguage), regardless of the transcript's language.")
        } else {
            sections.append("Reply in the same language as the transcript.")
        }
        return sections.joined(separator: "\n\n")
    }

    private func levelSection(_ level: CleanupLevel) -> String {
        switch level {
        case .none, .light:
            return """
                You clean up raw speech-to-text dictation. Add correct punctuation, \
                capitalization, and paragraph breaks to the transcript. Do not remove or \
                reword anything else — keep every word the speaker said.
                """
        case .medium:
            return """
                You clean up raw speech-to-text dictation. Rewrite the transcript as the \
                text the speaker intended to type:
                - Remove filler words (um, uh, you know, like) and false starts.
                - Add correct punctuation, capitalization, and paragraph breaks.
                - Keep the speaker's wording and meaning. Do not embellish, summarize, or add content.
                """
        case .high:
            return """
                You clean up raw speech-to-text dictation. Rewrite the transcript as the \
                polished text the speaker intended to type:
                - Remove filler words (um, uh, you know, like) and false starts.
                - Add correct punctuation, capitalization, and paragraph breaks.
                - Apply self-corrections: if the speaker says "scratch that", "no wait", \
                "actually, make that...", or restates something, keep only the corrected version.
                - Format spoken lists as numbered or bulleted lists when clearly intended.
                - Keep the speaker's wording and meaning. Do not embellish, summarize, or add content.
                """
        }
    }

    private func styleSection(_ style: StylePreset) -> String? {
        switch style {
        case .neutral:
            return nil
        case .casual:
            return """
                Style: casual message. Relaxed punctuation and contractions are fine — keep \
                the speaker's informal tone. Do not formalize greetings or sign-offs.
                """
        case .polished:
            return """
                Style: polished writing. Use complete sentences and proper grammar \
                throughout. Preserve any greetings and sign-offs the speaker dictated.
                """
        case .technical:
            return """
                Style: technical text. Preserve identifiers exactly as spoken: keep \
                camelCase, snake_case, file paths, URLs, and code symbols verbatim — never \
                autocorrect, re-space, or re-case them. Use plain ASCII quotes (' and ") only.
                """
        }
    }
}
