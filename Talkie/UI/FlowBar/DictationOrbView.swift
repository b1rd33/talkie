import Combine
import SwiftUI
import ThinkingOrbsKit

/// The upstream renderer uses a frozen frame driven by our common-mode clock,
/// so it also animates while Talkie's nonactivating panel is behind another app.
struct DictationOrbView: View {
    let presentation: PillPresentation
    let levelSource: any AudioLevelReading
    @State private var time = 1.7
    @State private var level: Float = 0

    private var state: OrbState {
        switch presentation.state {
        case .idle, .success: .breathing
        case .recording: .listening
        case .transcribing: .searching
        case .cleaning: .composing
        case .inserting: .shaping
        case .error: .working
        }
    }

    var body: some View {
        if presentation.isActive && !presentation.reduceMotion {
            orb.onReceive(Timer.publish(every: 1.0 / 30, on: .main, in: .common).autoconnect()) { date in
                time = date.timeIntervalSinceReferenceDate
                let target = max(0, min(1, levelSource.latestLevel))
                level += (target - level) * (target > level ? 0.65 : 0.18)
            }
        } else {
            orb
        }
    }

    private var orb: some View {
        ThinkingOrb(state: state, size: .px64, displaySize: 44)
            .orbFrozenTime(presentation.reduceMotion ? 1.7 : time)
            .scaleEffect(presentation.visualPhase == .recording && !presentation.reduceMotion
                         ? 0.86 + CGFloat(sqrt(level)) * 0.32 : 1)
            .accessibilityHidden(true)
    }
}

struct PillGlassSurface: ViewModifier {
    let increasedContrast: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency || increasedContrast {
            content.background(.background, in: Capsule())
                .overlay(Capsule().strokeBorder(.primary, lineWidth: 1))
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.clear, in: Capsule())
        } else {
            content.background(.ultraThinMaterial, in: Capsule())
        }
    }
}
