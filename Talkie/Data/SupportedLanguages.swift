import Foundation

/// The output/transcription languages offered in Settings — single source shared by
/// Simple and Advanced panes so a persisted `pinnedLanguage` always has a matching
/// picker row. Codes are ISO-639-1 (sent to the ASR verbatim); nil = auto-detect.
enum SupportedLanguages {
    static let all: [(name: String, code: String?)] = [
        ("Auto-detect", nil), ("English", "en"), ("German", "de"), ("French", "fr"),
        ("Spanish", "es"), ("Italian", "it"), ("Portuguese", "pt"), ("Dutch", "nl"),
        ("Polish", "pl"), ("Russian", "ru"), ("Ukrainian", "uk"), ("Turkish", "tr"),
        ("Japanese", "ja"), ("Korean", "ko"), ("Chinese", "zh"), ("Hindi", "hi"),
    ]
}
