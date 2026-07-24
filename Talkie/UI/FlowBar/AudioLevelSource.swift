import Foundation

/// The only recorder surface the pill needs. Keeping this tiny makes production
/// waveform rendering deterministic and independently testable.
@MainActor
protocol AudioLevelReading: AnyObject {
    var latestLevel: Float { get }
}

extension AudioRecorder: AudioLevelReading {}

enum SimulatedAudioFixture: String, CaseIterable, Sendable {
    case silence
    case quiet
    case conversation
    case energetic
}

/// Seeded, frame-addressable audio levels for deterministic animation previews.
final class SimulatedAudioLevelSource: AudioLevelReading {
    private let seed: UInt64
    var fixture: SimulatedAudioFixture
    var frame = 0

    init(seed: UInt64, fixture: SimulatedAudioFixture) {
        self.seed = seed
        self.fixture = fixture
    }

    @MainActor var latestLevel: Float { level(atFrame: frame) }

    func level(atFrame frame: Int) -> Float {
        let noise = unitNoise(frame: frame)
        guard fixture != .silence else { return noise * 0.02 }

        let cycle = frame % 96
        let speechEnvelope: Float
        switch cycle {
        case 0..<7, 77..<96:
            speechEnvelope = 0.05
        case 7..<18:
            speechEnvelope = Float(cycle - 7) / 11
        case 67..<77:
            speechEnvelope = Float(77 - cycle) / 10
        default:
            let cadence = (sin(Float(frame) * 0.31) + 1) * 0.18
            speechEnvelope = 0.58 + cadence
        }

        let range: (floor: Float, amplitude: Float) = switch fixture {
        case .silence: (0, 0)
        case .quiet: (0.025, 0.35)
        case .conversation: (0.04, 0.68)
        case .energetic: (0.07, 0.9)
        }
        return min(1, max(0, range.floor + speechEnvelope * range.amplitude * (0.72 + noise * 0.28)))
    }

    private func unitNoise(frame: Int) -> Float {
        var value = seed &+ UInt64(bitPattern: Int64(frame)) &* 0x9E3779B97F4A7C15
        value ^= value >> 12
        value ^= value << 25
        value ^= value >> 27
        value &*= 0x2545F4914F6CDD1D
        return Float(value & 0xFFFF) / Float(0xFFFF)
    }
}
