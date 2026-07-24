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
    static let audioRetentionSummary = "Successful audio is deleted after transcription unless Keep audio recordings is enabled. Failed or cancelled audio may stay local for retry."
}
