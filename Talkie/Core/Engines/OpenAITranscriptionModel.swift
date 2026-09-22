enum OpenAITranscriptionModel: String, CaseIterable, Sendable {
    case gptTranscribe = "gpt-transcribe"
    case gptLiveTranscribe = "gpt-live-transcribe"
    case gpt4oTranscribe = "gpt-4o-transcribe"
    case gpt4oMiniTranscribe = "gpt-4o-mini-transcribe"
    case gptRealtimeWhisper = "gpt-realtime-whisper"

    var supportsKeywords: Bool {
        self == .gptTranscribe || self == .gptLiveTranscribe
    }

    var supportsDelay: Bool { self == .gptLiveTranscribe }

    var isLegacy: Bool {
        switch self {
        case .gptTranscribe, .gptLiveTranscribe:
            false
        default:
            true
        }
    }
}

enum RealtimeTranscriptionDelay: String, CaseIterable, Sendable {
    case minimal
    case low
    case medium
    case high
    case xhigh

    var title: String {
        switch self {
        case .minimal: "Fastest"
        case .low: "Fast"
        case .medium: "Balanced"
        case .high: "Accurate"
        case .xhigh: "Most accurate"
        }
    }
}
