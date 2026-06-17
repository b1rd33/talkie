import Combine
import SwiftUI

/// Holds the rolling, smoothed mic-level history for the waveform. A reference
/// type so the Canvas can advance it per animation frame without it being
/// SwiftUI state; `advance(to:)` is idempotent per timeline date so repeated
/// renders of the same frame don't double-scroll.
final class WaveformBuffer {
    private(set) var samples: [Float]
    private var smoother = WaveformSmoother()
    private var lastDate: Date?

    init(count: Int) { samples = Array(repeating: 0, count: count) }

    func advance(to date: Date, level: Float) {
        guard date != lastDate else { return }
        lastDate = date
        let v = smoother.update(target: level)
        samples.removeFirst()
        samples.append(v)
    }
}

/// A live audio waveform drawn with a single `Canvas` (one view, redrawn at the
/// display's animation cadence) instead of N individual bar views. Renders only
/// while a recording is active — `FlowBarView` shows it for the `.recording`
/// state, so there's no always-on idle timer.
struct WaveformCanvasView: View {
    let recorder: AudioRecorder
    var color: Color = .primary
    var barCount = 28
    var barWidth: CGFloat = 2.5
    var gap: CGFloat = 2.5

    @State private var buffer: WaveformBuffer
    /// Bumped each timer tick; read in `body` so the `Canvas` re-renders on every tick.
    @State private var tick = 0
    /// A main-runloop, common-mode timer drives the redraw. `TimelineView(.animation)`
    /// does NOT tick inside the pill's `.nonactivatingPanel` accessory window, so the
    /// Canvas froze at its first frame and the waveform never animated. A common-mode
    /// main-runloop timer fires regardless of key-window status; it lives only as long
    /// as this view (shown only during `.recording`), so there's no idle cost.
    private let clock = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    init(recorder: AudioRecorder, color: Color = .primary, barCount: Int = 28) {
        self.recorder = recorder
        self.color = color
        self.barCount = barCount
        _buffer = State(initialValue: WaveformBuffer(count: barCount))
    }

    var body: some View {
        let _ = tick // establish a body dependency so each tick re-renders the Canvas
        Canvas { ctx, size in
            let samples = buffer.samples
            let n = samples.count
            let totalWidth = CGFloat(n) * barWidth + CGFloat(n - 1) * gap
            var x = (size.width - totalWidth) / 2
            for s in samples {
                let h = max(3, CGFloat(s) * size.height)
                let rect = CGRect(x: x, y: (size.height - h) / 2, width: barWidth, height: h)
                ctx.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(color))
                x += barWidth + gap
            }
        }
        .frame(width: CGFloat(barCount) * (barWidth + gap), height: 24)
        .onReceive(clock) { _ in
            buffer.advance(to: Date(), level: recorder.latestLevel)
            tick &+= 1
        }
    }
}
