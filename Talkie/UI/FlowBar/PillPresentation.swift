import Foundation

/// Privacy-safe, value-based input for the floating pill renderer.
/// Transcript, context, clipboard, and credential data cannot be represented here.
struct PillPresentation: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case idle
        case recording(handsFree: Bool)
        case transcribing
        case cleaning
        case inserting
        case success
        case error

        static func map(_ state: DictationState, handsFree: Bool,
                        showSuccess: Bool = false) -> Self {
            switch state {
            case .idle: showSuccess ? .success : .idle
            case .recording: .recording(handsFree: handsFree)
            case .transcribing: .transcribing
            case .cleaning: .cleaning
            case .inserting: .inserting
            case .error: .error
            }
        }
    }

    var state: State
    var style: PillStyle
    var elapsed: TimeInterval
    var audioLevel: Float
    var errorMessage: String?
    var offline: Bool
    var cleanupDegraded: Bool
    var reduceMotion: Bool
    var increasedContrast: Bool
    var isInstant = false

    var statusLabel: String? {
        switch state {
        case .transcribing: "Transcribing…"
        case .cleaning: "Cleaning…"
        case .inserting: "Inserting…"
        default: nil
        }
    }

    var isActive: Bool {
        switch state {
        case .idle, .success: false
        default: true
        }
    }

    var accessibilityLabel: String {
        switch state {
        case .idle:
            return "Talkie ready"
        case .recording(let handsFree):
            var parts = [handsFree ? "Hands-free recording" : "Recording",
                         "\(max(0, Int(elapsed.rounded(.down)))) seconds"]
            if offline { parts.append("offline mode") }
            if cleanupDegraded { parts.append("raw transcript fallback") }
            return parts.joined(separator: ", ")
        case .transcribing:
            return "Transcribing dictation"
        case .cleaning:
            return "Cleaning dictation"
        case .inserting:
            return "Inserting dictation"
        case .success:
            return "Dictation inserted"
        case .error:
            return "Dictation failed"
        }
    }

    static func preview(_ state: State, errorMessage: String? = nil) -> Self {
        Self(state: state,
             style: .bareWaveform,
             elapsed: 4,
             audioLevel: 0.42,
             errorMessage: errorMessage,
             offline: false,
             cleanupDegraded: false,
             reduceMotion: false,
             increasedContrast: false)
    }
}
