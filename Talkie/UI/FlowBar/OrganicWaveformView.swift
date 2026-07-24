import Combine
import SwiftUI

/// The three chromeless production waveform treatments. Each uses the real
/// recorder level, but never receives transcript or provider data.
struct OrganicWaveformView: View {
    let style: PillStyle
    let levelSource: any AudioLevelReading
    let presentation: PillPresentation
    var color: Color = .primary

    @State private var buffer: OrganicWaveBuffer
    @State private var tick = 0
    private let clock = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    init(style: PillStyle, levelSource: any AudioLevelReading,
         presentation: PillPresentation, color: Color = .primary) {
        self.style = style
        self.levelSource = levelSource
        self.presentation = presentation
        self.color = color
        _buffer = State(initialValue: OrganicWaveBuffer(initialLevel: presentation.audioLevel))
    }

    var body: some View {
        let _ = tick
        canvas
            .frame(width: 116, height: 26)
            .onReceive(clock) { date in
                guard presentation.isActive, !presentation.reduceMotion else { return }
                buffer.advance(to: date, level: levelSource.latestLevel)
                tick &+= 1
            }
            .accessibilityHidden(true)
    }

    private var canvas: some View {
        Canvas { context, size in
            let level = max(CGFloat(buffer.level), CGFloat(presentation.audioLevel))
            let phase = presentation.reduceMotion ? 0 : CGFloat(buffer.frame) * rate
            switch style {
            case .inkLine:
                drawLine(in: &context, size: size, level: level, phase: phase, lane: 0,
                         character: 0.18, amplitude: 10, opacity: 0.9,
                         width: presentation.increasedContrast ? 2.2 : 1.35)
            case .calmFlowRibbon:
                for lane in 0..<3 {
                    drawLine(in: &context, size: size, level: level,
                             phase: phase + CGFloat(lane) * 0.58, lane: lane,
                             character: 0.44 + CGFloat(lane) * 0.11,
                             amplitude: 7 + CGFloat(lane) * 3,
                             opacity: lane == 1 ? 0.92 : 0.34,
                             width: lane == 1 ? (presentation.increasedContrast ? 2.7 : 2) : 1)
                }
            case .bareWave:
                drawLine(in: &context, size: size, level: level, phase: phase, lane: 0,
                         character: 0.31, amplitude: 14, opacity: 0.9,
                         width: presentation.increasedContrast ? 2.2 : 1.45)
            default:
                break
            }
            drawTerminalStateMarker(in: &context, size: size)
        }
    }

    private var rate: CGFloat {
        switch style {
        case .inkLine: 0.085
        case .calmFlowRibbon: 0.065
        default: 0.095
        }
    }

    private func drawLine(in context: inout GraphicsContext, size: CGSize, level: CGFloat,
                          phase: CGFloat, lane: Int, character: CGFloat,
                          amplitude: CGFloat, opacity: Double, width: CGFloat) {
        var path = Path()
        for x in stride(from: 0.0, through: size.width, by: 1.5) {
            let position = x / size.width
            let envelope = pow(sin(position * .pi), style == .calmFlowRibbon ? 1.45 : 1.8)
            let y = size.height / 2 + organicWave(at: position, phase: phase, character: character) *
                amplitude * envelope * (level + 0.12)
            x == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
        }
        context.stroke(path, with: .color(color.opacity(opacity)), lineWidth: width)
    }

    private func drawTerminalStateMarker(in context: inout GraphicsContext, size: CGSize) {
        let marker: Color?
        switch presentation.state {
        case .success: marker = .green
        case .error: marker = .red
        default: marker = nil
        }
        guard let marker else { return }
        context.fill(Path(ellipseIn: CGRect(x: size.width - 7, y: size.height / 2 - 3,
                                           width: 6, height: 6)),
                     with: .color(marker.opacity(0.82)))
    }
}

final class OrganicWaveBuffer {
    private var smoother = WaveformSmoother()
    private var lastDate: Date?
    private(set) var level: Float
    private(set) var frame = 0

    init(initialLevel: Float) { level = min(max(initialLevel, 0), 1) }

    func advance(to date: Date, level target: Float) {
        guard date != lastDate else { return }
        lastDate = date
        level = smoother.update(target: target)
        frame &+= 1
    }
}

/// A low-frequency gesture with a quiet harmonic undertow. Incommensurate
/// frequencies keep it from reading as a mechanical oscilloscope trace.
private func organicWave(at position: CGFloat, phase: CGFloat, character: CGFloat) -> CGFloat {
    let drift = sin(position * .pi * (2.15 + character) + phase * 0.72)
    let undertow = sin(position * .pi * (4.7 - character) - phase * 0.37 + 1.2) * 0.32
    let breath = sin(position * .pi * 1.18 + phase * 0.21 - 0.8) * 0.16
    return (drift + undertow + breath) / 1.48
}
