import Foundation

/// Pure decision logic for the Settings cleanup-provider credential warning.
///
/// When the selected cleanup provider has no API key, `CleanupService` throws
/// `missingAPIKey` on every dictation and the coordinator silently inserts raw,
/// unpolished text. Surfacing the mismatch in Settings turns a confusing "why is
/// my text not cleaned up?" into an actionable message.
enum CleanupCredentialWarning {
    /// Returns warning text when the selected provider lacks its key OR the model
    /// name is mispaired with the provider (a silent-degradation path), else nil.
    /// A missing key takes priority over a mismatch.
    static func message(cleanupProvider: String, cleanupModel: String = "",
                        hasOpenAIKey: Bool, hasOpenRouterKey: Bool) -> String? {
        let isOpenAI = cleanupProvider == "openai"
        // 1) Missing key for the selected provider.
        if isOpenAI, !hasOpenAIKey {
            return "Cleanup is set to OpenAI but no OpenAI key is set — dictations will insert raw, unpolished text. Add an OpenAI key or switch cleanup to OpenRouter."
        }
        if !isOpenAI, !hasOpenRouterKey {
            return "Cleanup is set to OpenRouter but no OpenRouter key is set — dictations will insert raw, unpolished text. Add an OpenRouter key or switch providers."
        }
        // 2) Provider/model mispairing. OpenRouter model ids are "vendor/model"
        //    (contain a slash); OpenAI ids never do. A mismatch makes the cleanup
        //    request 4xx and silently fall back to raw text (the "RAW" pill badge).
        let modelLooksOpenRouter = cleanupModel.contains("/")
        if isOpenAI, modelLooksOpenRouter {
            return "Cleanup model \"\(cleanupModel)\" is an OpenRouter-style name but the provider is OpenAI — cleanup will fail and insert raw text. Pick an OpenAI model (no \"vendor/\" prefix) or switch the provider to OpenRouter."
        }
        if !isOpenAI, !cleanupModel.isEmpty, !modelLooksOpenRouter {
            return "Cleanup model \"\(cleanupModel)\" looks like an OpenAI model but the provider is OpenRouter — cleanup may fail and insert raw text. Use a \"vendor/model\" name or switch the provider to OpenAI."
        }
        return nil
    }
}
