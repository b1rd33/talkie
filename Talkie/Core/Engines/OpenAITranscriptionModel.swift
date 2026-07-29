import Foundation

enum TranscriptionWorkflow: Equatable {
    case batch
    case realtime
}

enum OpenAITranscriptionModel: String, CaseIterable, Sendable {
    case gptTranscribe = "gpt-transcribe"
    case gptLiveTranscribe = "gpt-live-transcribe"
    case gpt4oTranscribe = "gpt-4o-transcribe"
    case gpt4oMiniTranscribe = "gpt-4o-mini-transcribe"
    case gptRealtimeWhisper = "gpt-realtime-whisper"

    var workflow: TranscriptionWorkflow {
        switch self {
        case .gptLiveTranscribe, .gptRealtimeWhisper:
            .realtime
        case .gptTranscribe, .gpt4oTranscribe, .gpt4oMiniTranscribe:
            .batch
        }
    }

    var supportsKeywords: Bool {
        self == .gptTranscribe || self == .gptLiveTranscribe
    }

    var supportsMultipleLanguages: Bool { supportsKeywords }
    var supportsDelay: Bool { self == .gptLiveTranscribe }
    var returnsDetectedLanguages: Bool { self == .gptTranscribe }

    var isLegacy: Bool {
        switch self {
        case .gptTranscribe, .gptLiveTranscribe:
            false
        default:
            true
        }
    }

    var pricePerMinute: Double {
        switch self {
        case .gptTranscribe: 0.0045
        case .gptLiveTranscribe, .gptRealtimeWhisper: 0.017
        case .gpt4oMiniTranscribe: 0.003
        case .gpt4oTranscribe: 0.006
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
