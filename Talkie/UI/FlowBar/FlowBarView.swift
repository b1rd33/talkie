import SwiftUI

/// Production adapter. It converts observable app state into the same privacy-safe
/// value model rendered by the production Flow Bar.
struct FlowBarView: View {
    let coordinator: DictationCoordinator
    let recorder: AudioRecorder
    @Environment(SettingsStore.self) private var settings: SettingsStore?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    var onHideForHour: () -> Void = {}
    var onHidePermanently: () -> Void = {}

    @State private var showCompletionExit = false
    @State private var recordingStarted = Date()

    private var presentation: PillPresentation {
        let errorMessage: String? = if case .error(let message) = coordinator.state {
            message
        } else {
            nil
        }
        return PillPresentation(
            state: .map(coordinator.state,
                        handsFree: coordinator.isHandsFree,
                        showSuccess: showCompletionExit),
            style: settings?.pillStyle ?? .default,
            elapsed: max(0, Date().timeIntervalSince(recordingStarted)),
            audioLevel: recorder.latestLevel,
            errorMessage: errorMessage,
            offline: coordinator.offlineBadgeVisible,
            cleanupDegraded: coordinator.cleanupDegraded,
            reduceMotion: reduceMotion,
            increasedContrast: colorSchemeContrast == .increased,
            isInstant: settings?.engineMode == "instant",
            showsTimer: settings?.showPillTimer ?? false,
            showsCancelButton: settings?.showPillCancelButton ?? false)
    }

    var body: some View {
        PillRendererView(
            presentation: presentation,
            levelSource: recorder,
            recordingStartedAt: recordingStarted,
            cleanupFailureReason: coordinator.cleanupFailureReason,
            onCancel: { coordinator.cancel() },
            onHideForHour: onHideForHour,
            onHidePermanently: onHidePermanently)
        .onChange(of: coordinator.state) { _, newState in
            if newState == .recording { recordingStarted = .now }
        }
        .onChange(of: coordinator.lastCompletedAt) { _, newValue in
            guard newValue != nil else { return }
            showCompletionExit = true
            Task {
                try? await Task.sleep(for: .seconds(PillMotionProfile.calmFlow.successDuration))
                showCompletionExit = false
            }
        }
    }

    /// Last `max` Characters of `s` (grapheme-safe — never splits an emoji).
    static func tail(_ s: String, max: Int) -> String {
        s.count <= max ? s : String(s.suffix(max))
    }

}

/// The shared native renderer used by the production non-activating panel.
struct PillRendererView: View {
    let presentation: PillPresentation
    let levelSource: any AudioLevelReading
    var recordingStartedAt: Date?
    var cleanupFailureReason: String?
    var onCancel: () -> Void = {}
    var onHideForHour: () -> Void = {}
    var onHidePermanently: () -> Void = {}

    @State private var handsFreeExpanded = false
    @State private var processingRingExpanded = false

    private var style: PillStyle { presentation.style }
    private var isChromeless: Bool {
        style == .bareWaveform || style == .inkLine || style == .calmFlowRibbon ||
            style == .bareWave || style == .hidden
    }
    private var isOrganicWaveform: Bool {
        style == .inkLine || style == .calmFlowRibbon || style == .bareWave
    }
    private var contentForeground: Color { style == .dynamicIsland ? .white : .primary }
    private var motion: PillMotionProfile {
        .resolve(reduceMotion: presentation.reduceMotion)
    }
    private var isHandsFree: Bool {
        if case .recording(handsFree: true) = presentation.state { true } else { false }
    }

    var body: some View {
        Group {
            switch presentation.state {
            case .idle:
                idleView
            case .recording:
                activePill {
                    if style == .dynamicIsland {
                        Circle().fill(.red).frame(width: 7, height: 7)
                    }
                    if isOrganicWaveform {
                        OrganicWaveformView(style: style, levelSource: levelSource,
                                            presentation: presentation, color: contentForeground)
                    } else {
                        WaveformCanvasView(recorder: levelSource, color: contentForeground)
                            .accessibilityHidden(true)
                    }
                    if presentation.showsTimer { timerView }
                    if presentation.showsCancelButton { cancelButton }
                }
            case .transcribing, .cleaning, .inserting, .success:
                activePill {
                    processingRing
                    if presentation.showsCancelButton && presentation.isCancellable {
                        cancelButton
                    }
                }
            case .error:
                errorView(presentation.errorMessage ?? "Dictation failed")
            }
        }
        .frame(width: PillLayout.panelSize.width,
               height: PillLayout.panelSize.height,
               alignment: style == .dynamicIsland ? .top : .bottom)
        .padding(style == .dynamicIsland ? .top : .bottom, 2)
        .scaleEffect(isHandsFree
                     ? (handsFreeExpanded ? motion.handsFreeMaximumScale
                                          : motion.handsFreeMinimumScale)
                     : 1)
        .animation(.easeOut(duration: motion.entryDuration),
                   value: presentation.visualPhase)
        .overlay(alignment: .topTrailing) {
            if presentation.offline {
                Text("offline")
                    .font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.orange.opacity(0.9), in: Capsule())
                    .foregroundStyle(.white)
                    .offset(y: -4)
            }
        }
        .overlay(alignment: .topLeading) {
            if presentation.cleanupDegraded {
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("RAW")
                }
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.yellow)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(.black.opacity(0.35), in: Capsule())
                .shadow(color: .black.opacity(0.5), radius: 1.5, y: 0.5)
                .offset(y: -4)
                .help(cleanupFailureReason ?? "Cleanup failed — inserted the raw transcript.")
            }
        }
        .contextMenu {
            Button("Hide for 1 hour") { onHideForHour() }
            Button("Hide permanently") { onHidePermanently() }
        }
        .modifier(PillAccessibilityModifier(
            presentation: presentation,
            onCancel: onCancel,
            onHideForHour: onHideForHour,
            onHidePermanently: onHidePermanently))
        .onAppear { updateHandsFreeAnimation() }
        .onChange(of: isHandsFree) { _, _ in updateHandsFreeAnimation() }
        .onChange(of: presentation.reduceMotion) { _, _ in updateHandsFreeAnimation() }
        .onAppear { updateProcessingRingAnimation() }
        .onChange(of: presentation.visualPhase) { _, _ in updateProcessingRingAnimation() }
        .onChange(of: presentation.reduceMotion) { _, _ in updateProcessingRingAnimation() }
    }

    @ViewBuilder private var timerView: some View {
        if let recordingStartedAt {
            Text(recordingStartedAt, style: .timer)
                .font(.caption.monospacedDigit())
                .foregroundStyle(contentForeground.opacity(0.85))
        } else {
            Text(Self.formattedElapsed(presentation.elapsed))
                .font(.caption.monospacedDigit())
                .foregroundStyle(contentForeground.opacity(0.85))
        }
    }

    static func formattedElapsed(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded(.down)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func updateHandsFreeAnimation() {
        guard isHandsFree, !presentation.reduceMotion else {
            handsFreeExpanded = false
            return
        }
        handsFreeExpanded = false
        withAnimation(.easeInOut(duration: motion.handsFreeDuration).repeatForever(autoreverses: true)) {
            handsFreeExpanded = true
        }
    }

    private var processingRing: some View {
        Circle()
            .stroke(
                contentForeground.opacity(presentation.increasedContrast ? 0.9 : 0.62),
                lineWidth: presentation.increasedContrast ? 2 : 1.5)
            .frame(width: 16, height: 16)
            .scaleEffect(presentation.reduceMotion
                         ? 1
                         : (processingRingExpanded
                            ? motion.processingBreathMaximumScale
                            : motion.processingBreathMinimumScale))
            .accessibilityHidden(true)
    }

    private func updateProcessingRingAnimation() {
        guard presentation.visualPhase == .processing,
              !presentation.reduceMotion,
              motion.processingBreathDuration > 0
        else {
            processingRingExpanded = false
            return
        }
        processingRingExpanded = false
        withAnimation(
            .easeInOut(duration: motion.processingBreathDuration)
                .repeatForever(autoreverses: true)
        ) {
            processingRingExpanded = true
        }
    }

    @ViewBuilder private var idleView: some View {
        switch style {
        case .hidden:
            Color.clear.frame(width: 1, height: 1)
        case .bareWaveform:
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(Color.primary.opacity(0.4)).frame(width: 4, height: 4)
                }
            }
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
        case .inkLine, .calmFlowRibbon, .bareWave:
            OrganicWaveformView(style: style, levelSource: levelSource,
                                presentation: presentation, color: contentForeground)
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
        case .frostedGlass:
            Capsule().fill(.ultraThinMaterial)
                .frame(width: 60, height: 11)
                .overlay(Capsule().strokeBorder(.white.opacity(presentation.increasedContrast ? 0.7 : 0.3),
                                                lineWidth: presentation.increasedContrast ? 1 : 0.5))
                .shadow(color: .black.opacity(0.2), radius: 4, y: 1)
        case .dynamicIsland:
            Capsule().fill(.black)
                .frame(width: 96, height: 20)
                .overlay(alignment: .trailing) {
                    Circle().fill(.white.opacity(0.18)).frame(width: 6, height: 6).padding(.trailing, 8)
                }
                .shadow(color: .black.opacity(0.35), radius: 5, y: 2)
        }
    }

    @ViewBuilder private func errorView(_ message: String) -> some View {
        if isChromeless {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                Text(message).foregroundStyle(.primary).lineLimit(1).truncationMode(.tail)
            }
            .font(.caption)
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
        } else {
            content(accent: .red) {
                Text(message).font(.caption)
                    .foregroundStyle(style == .frostedGlass
                                     ? AnyShapeStyle(.primary) : AnyShapeStyle(.white))
                    .lineLimit(1).truncationMode(.tail)
            }
        }
    }

    private var cancelButton: some View {
        Button(action: onCancel) {
            Image(systemName: "xmark")
                .font(.caption.bold())
                .foregroundStyle(contentForeground.opacity(0.85))
        }
        .buttonStyle(.plain)
        .help("Cancel dictation")
        .accessibilityLabel("Cancel dictation")
    }

    private func activePill(@ViewBuilder content: () -> some View) -> some View {
        self.content(accent: nil) { HStack(spacing: 8) { content() } }
            .transition(.scale(scale: motion.entryMinimumScale).combined(with: .opacity))
    }

    @ViewBuilder
    private func content(accent: Color?, @ViewBuilder _ inner: () -> some View) -> some View {
        switch style {
        case .bareWaveform, .inkLine, .calmFlowRibbon, .bareWave, .hidden:
            inner()
                .frame(height: 34)
                .shadow(color: .black.opacity(0.4), radius: 4, y: 1)
        case .frostedGlass:
            inner()
                .padding(.horizontal, 16)
                .frame(height: 34)
                .background(accent.map { AnyShapeStyle($0.opacity(0.55)) }
                            ?? AnyShapeStyle(.ultraThinMaterial), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(presentation.increasedContrast ? 0.7 : 0.3),
                                                lineWidth: presentation.increasedContrast ? 1 : 0.5))
                .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
        case .dynamicIsland:
            inner()
                .padding(.horizontal, 16)
                .frame(height: 34)
                .background(accent?.opacity(0.85) ?? .black.opacity(0.78), in: Capsule())
                .shadow(color: .black.opacity(0.3), radius: 8, y: 2)
        }
    }
}

private struct PillAccessibilityModifier: ViewModifier {
    let presentation: PillPresentation
    let onCancel: () -> Void
    let onHideForHour: () -> Void
    let onHidePermanently: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        let accessible = content
            .accessibilityElement(children: .contain)
            .accessibilityLabel(presentation.accessibilityLabel)
            .accessibilityAction(named: "Hide for 1 hour", onHideForHour)
            .accessibilityAction(named: "Hide permanently", onHidePermanently)

        if presentation.isCancellable {
            accessible.accessibilityAction(named: "Cancel dictation", onCancel)
        } else {
            accessible
        }
    }
}
