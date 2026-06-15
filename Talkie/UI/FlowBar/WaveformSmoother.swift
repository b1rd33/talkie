import Foundation

/// Exponential-moving-average smoother for the live mic level with separate
/// attack (rise) and release (fall) rates — fast to jump up on a syllable,
/// slower to decay, which reads as a natural waveform instead of the jittery
/// raw `recorder.latestLevel`. Pure value type so it's unit-testable away from
/// any SwiftUI timing.
struct WaveformSmoother {
    /// 0…1 — fraction of the gap to the target closed per step when rising.
    let attack: Float
    /// 0…1 — fraction closed per step when falling.
    let release: Float
    private(set) var value: Float = 0

    init(attack: Float = 0.55, release: Float = 0.15) {
        self.attack = attack
        self.release = release
    }

    /// Advance one step toward `target` and return the new smoothed value (0…1).
    @discardableResult
    mutating func update(target: Float) -> Float {
        let clamped = min(max(target, 0), 1)
        let rate = clamped > value ? attack : release
        value += (clamped - value) * rate
        value = min(max(value, 0), 1)
        return value
    }
}
