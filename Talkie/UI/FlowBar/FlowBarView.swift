import SwiftUI

struct FlowBarView: View {
    let coordinator: DictationCoordinator
    let recorder: AudioRecorder
    /// Injected via .environment from FlowBarPanel — a plain stored property is
    /// NOT tracked by SwiftUI inside NSHostingView, so pillStyle/engineMode
    /// changes never re-rendered the pill (live-testing bug 2026-06-11).
    @Environment(SettingsStore.self) private var settings: SettingsStore?
    var onHideForHour: () -> Void = {}
    var onHidePermanently: () -> Void = {}

    @State private var levels: [Float] = Array(repeating: 0, count: 24)
    @State private var showCheckmark = false
    @State private var hovering = false
    @State private var recordingStarted = Date()
    private let timer = Timer.publish(every: 1.0 / 24, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            switch coordinator.state {
            case .idle:
                if showCheckmark {
                    pill(background: .green.opacity(0.85)) {
                        Image(systemName: "checkmark")
                            .font(.caption.bold()).foregroundStyle(.white)
                    }
                } else {
                    // Idle look depends on the chosen style:
                    // classic = slim notch (+ mic on hover), dot = small dot,
                    // hidden/compact = nothing until a dictation starts.
                    switch settings?.pillStyle ?? "classic" {
                    case "hidden", "compact":
                        Color.clear.frame(width: 1, height: 1)
                    case "dot":
                        Circle().fill(.black.opacity(0.55)).frame(width: 8, height: 8)
                    default: // classic — spec §7: idle slim notch, mic glyph on hover
                        Group {
                            if hovering {
                                pill {
                                    Image(systemName: "mic.fill")
                                        .font(.caption).foregroundStyle(.white.opacity(0.85))
                                }
                            } else {
                                Capsule().fill(.black.opacity(0.55))
                                    .frame(width: 56, height: 7)
                            }
                        }
                        .onHover { hovering = $0 }
                    }
                }
            case .recording:
                pill {
                    HStack(spacing: 8) {
                        if settings?.engineMode == "instant" {
                            Image(systemName: "bolt.fill").font(.system(size: 9)).foregroundStyle(.yellow)
                        }
                        HStack(spacing: 2.5) {
                            ForEach(levels.indices, id: \.self) { i in
                                Capsule().fill(.white)
                                    .frame(width: 2.5, height: max(3, CGFloat(levels[i]) * 26))
                            }
                        }
                        if settings?.pillStyle != "compact" { // compact: bars only, no timer
                            Text(recordingStarted, style: .timer) // spec §7: recording timer
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        cancelButton
                    }
                }
            case .transcribing, .cleaning, .inserting:
                pill {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small).tint(.white)
                        Text("Polishing…").font(.caption).foregroundStyle(.white.opacity(0.85))
                        cancelButton
                    }
                }
            case .error(let message):
                pill(background: .red.opacity(0.85)) {
                    Text(message).font(.caption).foregroundStyle(.white)
                        .lineLimit(1).truncationMode(.tail)
                }
            }
        }
        .frame(width: 260, height: 56, alignment: .bottom)
        .padding(.bottom, 2)
        .animation(.spring(duration: 0.25), value: coordinator.state)
        .animation(.spring(duration: 0.25), value: showCheckmark)
        .overlay(alignment: .topTrailing) {
            // Phase 3's offline-fallback badge (spec §10) — re-applied on top of
            // this full replacement; do not drop it.
            if coordinator.offlineBadgeVisible {
                Text("offline").font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.orange.opacity(0.9), in: Capsule()).foregroundStyle(.white)
                    .offset(y: -4)
            }
        }
        .overlay(alignment: .topLeading) {
            // spec §6/§10: cleanup failed → raw text was inserted + subtle warning
            if coordinator.cleanupDegraded {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2).foregroundStyle(.yellow)
                    .offset(y: -4)
                    .help("Cleanup failed — inserted the raw transcript")
            }
        }
        .contextMenu {
            Button("Hide for 1 hour") { onHideForHour() }
            Button("Hide permanently") { onHidePermanently() }
        }
        .onReceive(timer) { _ in
            guard coordinator.state == .recording else { return }
            levels.removeFirst()
            levels.append(recorder.latestLevel)
        }
        .onChange(of: coordinator.state) { _, newState in
            if newState == .recording { recordingStarted = .now }
        }
        .onChange(of: coordinator.lastCompletedAt) { _, newValue in
            guard newValue != nil else { return }
            showCheckmark = true
            Task {
                try? await Task.sleep(for: .milliseconds(800))
                showCheckmark = false
            }
        }
    }

    /// .plain draws no focusable bezel; the panel is .nonactivatingPanel, so the
    /// click is handled here while the target app keeps key status and its caret.
    private var cancelButton: some View {
        Button { coordinator.cancel() } label: {
            Image(systemName: "xmark")
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.85))
        }
        .buttonStyle(.plain)
        .help("Cancel dictation")
    }

    private func pill(background: Color = .black.opacity(0.78),
                      @ViewBuilder content: () -> some View) -> some View {
        content()
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(background, in: Capsule())
            .shadow(color: .black.opacity(0.3), radius: 8, y: 2)
    }
}
