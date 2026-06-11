import Foundation

/// Local cost estimation per dictation (Home spend dashboard).
/// Rates verified 2026-06-11 against OpenAI's pricing docs and OpenRouter's
/// model pages. Estimates only — OpenAI's billing API needs an admin key, and
/// OpenRouter's real balance is shown separately from /api/v1/credits.
enum PriceBook {
    /// ASR $/minute by the engine id stored in DictationRecord.engine.
    static let transcriptionPerMinute: [String: Double] = [
        "gpt-4o-mini-transcribe": 0.003,
        "gpt-4o-transcribe": 0.006,
        "realtime": 0.017,                          // gpt-realtime-whisper, billed by duration
        "mistralai/voxtral-mini-transcribe": 0.003, // OpenRouter
        "microsoft/mai-transcribe-1.5": 0.006,      // OpenRouter ($0.36/hr)
        "parakeet": 0,                              // local, free
        // Rest of OpenRouter's transcription category (scouted 2026-06-11):
        "openai/whisper-large-v3-turbo": 0.00067,   // $0.04/hr — cheapest, 99+ languages
        "openai/whisper-large-v3": 0.0015,
        "nvidia/parakeet-tdt-0.6b-v3": 0.0015,      // cloud parakeet (≠ local "parakeet")
        "qwen/qwen3-asr-flash-2026-02-10": 0.0021,
        "openai/gpt-4o-mini-transcribe": 0.003,     // via OpenRouter, token-billed ≈ same
        "openai/whisper-1": 0.006,
        "openai/gpt-4o-transcribe": 0.006,
        "google/chirp-3": 0.016,
    ]
    /// Legacy rows store engine "openai" without a model — assume mini pricing.
    static let fallbackPerMinute = 0.003

    /// Cleanup chat (input $/M tokens, output $/M tokens) by cleanup model id.
    static let cleanupPerMTokens: [String: (input: Double, output: Double)] = [
        "google/gemini-2.5-flash-lite": (0.10, 0.40),
        "google/gemini-2.5-flash": (0.30, 2.50),
    ]
    /// Unknown cleanup models (e.g. gpt-5.4-nano) get the cheap-tier estimate.
    static let fallbackCleanup: (input: Double, output: Double) = (0.10, 0.40)

    /// Rough token count: transcript words × 1.4, same in and out.
    static func estimate(engine: String, durationSec: Double,
                         cleanupModel: String?, wordCount: Int) -> Double {
        let perMinute = transcriptionPerMinute[engine] ?? fallbackPerMinute
        var cost = (durationSec / 60.0) * perMinute
        if let cleanupModel {
            let rate = cleanupPerMTokens[cleanupModel] ?? fallbackCleanup
            let tokens = Double(wordCount) * 1.4
            cost += (tokens / 1e6) * rate.input + (tokens / 1e6) * rate.output
        }
        return cost
    }
}
