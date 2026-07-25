enum PrivacyMode: CaseIterable {
    case onDeviceTranscription
    case cloudBatchTranscription
    case instantTranscription
    case cleanupAndContext

    var label: String {
        switch self {
        case .onDeviceTranscription: "On-device transcription"
        case .cloudBatchTranscription: "Cloud batch transcription"
        case .instantTranscription: "Instant transcription"
        case .cleanupAndContext: "Cleanup and context"
        }
    }
}

enum PrivacyCopy {
    static let policyLinkLabel = "Privacy and provider data flow"
    static let audioRetentionSummary = "Talkie attempts to delete audio after a successfully completed dictation unless Keep audio recordings is enabled. Failed, cancelled, or insertion-failed recordings—and files left by a deletion error—may remain locally for retry or recovery."
}
