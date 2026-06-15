import Foundation

/// Pure decision logic for the Settings cleanup-provider credential warning.
///
/// When the selected cleanup provider has no API key, `CleanupService` throws
/// `missingAPIKey` on every dictation and the coordinator silently inserts raw,
/// unpolished text. Surfacing the mismatch in Settings turns a confusing "why is
/// my text not cleaned up?" into an actionable message.
enum CleanupCredentialWarning {
    /// Returns warning text when the selected provider lacks its key, else nil.
    static func message(cleanupProvider: String,
                        hasOpenAIKey: Bool, hasOpenRouterKey: Bool) -> String? {
        switch cleanupProvider {
        case "openai":
            return hasOpenAIKey ? nil :
                "Cleanup is set to OpenAI but no OpenAI key is set — dictations will insert raw, unpolished text. Add an OpenAI key or switch cleanup to OpenRouter."
        default: // openrouter (and any unknown value, which CleanupService treats as OpenRouter)
            return hasOpenRouterKey ? nil :
                "Cleanup is set to OpenRouter but no OpenRouter key is set — dictations will insert raw, unpolished text. Add an OpenRouter key or switch providers."
        }
    }
}
