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

    init(recorder: AudioRecorder, color: Color = .primary, barCount: Int = 28) {
        self.recorder = recorder
        self.color = color
        self.barCount = barCount
        _buffer = State(initialValue: WaveformBuffer(count: barCount))
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { ctx, size in
                buffer.advance(to: timeline.date, level: recorder.latestLevel)
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
        }
        .frame(width: CGFloat(barCount) * (barWidth + gap), height: 24)
    }
}
