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

    @State private var showCheckmark = false
    @State private var recordingStarted = Date()

    private var style: PillStyle { settings?.pillStyle ?? .default }
    /// Chromeless styles float their content (waveform + text) with only a drop
    /// shadow; the others wrap it in a capsule. Bare waveform is the new default.
    private var isChromeless: Bool { style == .bareWaveform || style == .hidden }
    /// Foreground that reads on any wallpaper: `.primary` follows the system
    /// light/dark appearance for chromeless + glass; white on the dark capsule.
    private var contentForeground: Color { style == .dynamicIsland ? .white : .primary }

    var body: some View {
        Group {
            switch coordinator.state {
            case .idle:
                if showCheckmark { successView } else { idleView }
            case .recording:
                activePill {
                    if style == .dynamicIsland {
                        // The island's iconic leading "live" dot.
                        Circle().fill(.red).frame(width: 7, height: 7)
                    } else if settings?.engineMode == "instant" {
                        Image(systemName: "bolt.fill").font(.system(size: 9)).foregroundStyle(.yellow)
                    }
                    if showLiveText {
                        liveTextView
                    } else {
                        WaveformCanvasView(recorder: recorder, color: contentForeground)
                    }
                    Text(recordingStarted, style: .timer) // spec §7: recording timer
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(contentForeground.opacity(0.85))
                    cancelButton
                }
            case .transcribing, .cleaning, .inserting:
                activePill {
                    ProgressView().controlSize(.small).tint(contentForeground)
                    Text("Polishing…").font(.caption).foregroundStyle(contentForeground.opacity(0.85))
                    cancelButton
                }
            case .error(let message):
                errorView(message)
            }
        }
        // Dynamic Island docks at the top of the panel (which PillLayout pins to
        // top-center near the notch); every other style sits at the bottom.
        .frame(width: 260, height: 56, alignment: style == .dynamicIsland ? .top : .bottom)
        .padding(style == .dynamicIsland ? .top : .bottom, 2)
        .animation(.spring(duration: 0.3), value: coordinator.state)
        .animation(.spring(duration: 0.3), value: showCheckmark)
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
            // spec §6/§10: cleanup failed → raw text was inserted. A labeled "raw"
            // badge (not a bare triangle) makes the degraded state legible; the
            // tooltip carries the actual cause captured by the coordinator.
            if coordinator.cleanupDegraded {
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("RAW")
                }
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.yellow)
                // A subtle dark backing + shadow so the yellow stays legible on
                // any wallpaper without filling the badge yellow.
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(.black.opacity(0.35), in: Capsule())
                .shadow(color: .black.opacity(0.5), radius: 1.5, y: 0.5)
                .offset(y: -4)
                .help(coordinator.cleanupFailureReason
                      ?? "Cleanup failed — inserted the raw transcript.")
            }
        }
        .contextMenu {
            Button("Hide for 1 hour") { onHideForHour() }
            Button("Hide permanently") { onHidePermanently() }
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

    // MARK: live instant-transcript preview

    /// Show the streamed text instead of the waveform once instant has produced any.
    private var showLiveText: Bool {
        settings?.engineMode == "instant" && !coordinator.liveTranscript.isEmpty
    }

    /// The tail of the streaming transcript, fading in at the leading edge and
    /// scrolling within a fixed width so the pill never grows past 260×56.
    private var liveTextView: some View {
        Text(Self.tail(coordinator.liveTranscript, max: 42))
            .font(.caption)
            .foregroundStyle(contentForeground)
            .lineLimit(1)
            .truncationMode(.head)
            .frame(maxWidth: 140, alignment: .trailing)
            .mask(LinearGradient(colors: [.clear, .black, .black],
                                 startPoint: .leading, endPoint: .trailing))
            .animation(.spring(duration: 0.25), value: coordinator.liveTranscript)
    }

    /// Last `max` Characters of `s` (grapheme-safe — never splits an emoji).
    static func tail(_ s: String, max: Int) -> String {
        s.count <= max ? s : String(s.suffix(max))
    }

    // MARK: idle

    @ViewBuilder private var idleView: some View {
        switch style {
        case .hidden:
            Color.clear.frame(width: 1, height: 1) // panel is ordered out anyway
        case .bareWaveform:
            // Three faint dots — a calm "listening soon" hint, not a hard shape.
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(Color.primary.opacity(0.4)).frame(width: 4, height: 4)
                }
            }
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
        case .frostedGlass:
            // A small translucent glass lozenge that picks up the desktop behind it.
            Capsule().fill(.ultraThinMaterial)
                .frame(width: 60, height: 11)
                .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.2), radius: 4, y: 1)
        case .dynamicIsland:
            // A small black pill that reads as an extension of the camera notch;
            // it grows into the full island when a dictation starts.
            Capsule().fill(.black)
                .frame(width: 96, height: 20)
                .overlay(alignment: .trailing) {
                    Circle().fill(.white.opacity(0.18)).frame(width: 6, height: 6).padding(.trailing, 8)
                }
                .shadow(color: .black.opacity(0.35), radius: 5, y: 2)
        }
    }

    // MARK: success / error

    @ViewBuilder private var successView: some View {
        if isChromeless {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.green)
                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                .transition(.scale.combined(with: .opacity))
        } else {
            content(accent: .green) {
                Image(systemName: "checkmark").font(.caption.bold())
                    .foregroundStyle(style == .frostedGlass ? AnyShapeStyle(.green) : AnyShapeStyle(.white))
            }
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
                    .foregroundStyle(style == .frostedGlass ? AnyShapeStyle(.primary) : AnyShapeStyle(.white))
                    .lineLimit(1).truncationMode(.tail)
            }
        }
    }

    /// .plain draws no focusable bezel; the panel is .nonactivatingPanel, so the
    /// click is handled here while the target app keeps key status and its caret.
    private var cancelButton: some View {
        Button { coordinator.cancel() } label: {
            Image(systemName: "xmark")
                .font(.caption.bold())
                .foregroundStyle(contentForeground.opacity(0.85))
        }
        .buttonStyle(.plain)
        .help("Cancel dictation")
    }

    // MARK: chrome

    /// The active-state row of content, wrapped per style: chromeless styles get
    /// only a drop shadow; frosted glass a translucent capsule; dynamic island a
    /// dark capsule (interim until its phase).
    private func activePill(@ViewBuilder content: () -> some View) -> some View {
        self.content(accent: nil) {
            HStack(spacing: 8) { content() }
        }
    }

    /// `accent` nil = the style's neutral background (material or dark capsule);
    /// a color = a tinted background for success (green) / error (red).
    @ViewBuilder
    private func content(accent: Color?, @ViewBuilder _ inner: () -> some View) -> some View {
        switch style {
        case .bareWaveform, .hidden:
            inner()
                .frame(height: 34)
                .shadow(color: .black.opacity(0.4), radius: 4, y: 1)
        case .frostedGlass:
            inner()
                .padding(.horizontal, 16)
                .frame(height: 34)
                .background(accent.map { AnyShapeStyle($0.opacity(0.55)) } ?? AnyShapeStyle(.ultraThinMaterial),
                            in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 0.5))
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
