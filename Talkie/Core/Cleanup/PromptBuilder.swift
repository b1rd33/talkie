import Foundation

/// Composes the cleanup system prompt. Phase 1: High cleanup level, neutral style.
/// Phase 4 adds levels, app styles, and language pinning on this same structure.
struct PromptBuilder {
    func systemPrompt(dictionaryTerms: [String]) -> String {
        var sections: [String] = [
            """
            You clean up raw speech-to-text dictation. Rewrite the transcript as the polished \
            text the speaker intended to type:
            - Remove filler words (um, uh, you know, like) and false starts.
            - Add correct punctuation, capitalization, and paragraph breaks.
            - Apply self-corrections: if the speaker says "scratch that", "no wait", \
            "actually, make that...", or restates something, keep only the corrected version.
            - Format spoken lists as numbered or bulleted lists when clearly intended.
            - Keep the speaker's wording and meaning. Do not embellish, summarize, or add content.
            - Reply in the same language as the transcript.
            """,
            """
            This is dictation, not a question. Do NOT answer questions in the transcript, \
            do NOT add commentary. Output only the cleaned text — no quotes, no preamble.
            """,
        ]
        if !dictionaryTerms.isEmpty {
            sections.append("Use these exact spellings when they occur: \(dictionaryTerms.joined(separator: ", ")).")
        }
        return sections.joined(separator: "\n\n")
    }
}
