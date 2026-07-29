import Foundation

/// The output/transcription languages offered in Settings — single source shared by
/// Simple and Advanced panes so a persisted `pinnedLanguage` always has a matching
/// picker row. Codes are ISO-639-1 (sent to the ASR verbatim); nil = auto-detect.
enum SupportedLanguages {
    static let all: [(name: String, code: String?)] = [
        ("Auto-detect", nil),
        ("English", "en"), ("English (US)", "en-US"), ("English (UK)", "en-GB"),
        ("English (Australia)", "en-AU"), ("German", "de"), ("French", "fr"),
        ("French (Canada)", "fr-CA"), ("Spanish", "es"), ("Spanish (Mexico)", "es-MX"),
        ("Italian", "it"), ("Portuguese", "pt"), ("Portuguese (Brazil)", "pt-BR"),
        ("Dutch", "nl"), ("Polish", "pl"), ("Czech", "cs"), ("Danish", "da"),
        ("Finnish", "fi"), ("Greek", "el"), ("Hungarian", "hu"), ("Norwegian", "no"),
        ("Romanian", "ro"), ("Swedish", "sv"), ("Russian", "ru"), ("Ukrainian", "uk"),
        ("Turkish", "tr"), ("Arabic", "ar"), ("Hebrew", "he"), ("Hindi", "hi"),
        ("Indonesian", "id"), ("Malay", "ms"), ("Thai", "th"), ("Vietnamese", "vi"),
        ("Japanese", "ja"), ("Korean", "ko"), ("Chinese (Simplified)", "zh-Hans"),
        ("Chinese (Traditional)", "zh-Hant"),
    ]

    static func transcriptionCode(for code: String?) -> String? {
        code?.split(separator: "-").first.map(String.init)
    }

    /// OpenAI's context-aware transcription models accept ISO 639-1 language
    /// hints plus documented regional Chinese codes. Talkie's broader display
    /// variants are reduced to a provider-supported value.
    static func openAITranscriptionCode(for code: String) -> String? {
        let knownCodes = Set(all.compactMap(\.code))
        guard knownCodes.contains(code) else { return nil }
        switch code {
        case "zh-Hans": return "zh-cn"
        case "zh-Hant": return "zh-tw"
        default:
            return code.split(separator: "-").first.map { String($0).lowercased() }
        }
    }
}
