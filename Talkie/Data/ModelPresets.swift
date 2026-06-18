import Foundation

/// Canonical, known-good model IDs — the single source of truth shared by the
/// Settings preset menus and the built-in `DictationProfile`s. A test asserts every
/// built-in profile's model IDs are members of these lists so a profile can never
/// pin a typo'd or retired model.
///
/// Provider convention: OpenRouter model IDs are "vendor/model" (contain a slash);
/// OpenAI model IDs never do.
enum ModelPresets {
    static let transcription = ["gpt-4o-mini-transcribe", "gpt-4o-transcribe"]
    static let openrouterTranscription = ["mistralai/voxtral-mini-transcribe"]
    static let openaiCleanup = ["gpt-5.4-nano", "gpt-5.4-mini", "gpt-4.1-nano"]
    static let openrouterCleanup = ["google/gemini-2.5-flash-lite", "google/gemini-2.5-flash", "openai/gpt-5.4-nano"]
}
