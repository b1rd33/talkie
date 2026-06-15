import Foundation

/// The Flow Bar pill's visual style. Replaces the former raw strings
/// (classic/dot/compact/hidden) with a typed, migratable preference.
enum PillStyle: String, CaseIterable, Sendable {
    /// Chromeless live waveform; three faint dots when idle. The new default.
    case bareWaveform
    /// Black island docked top-center that morphs between idle and active.
    case dynamicIsland
    /// Translucent frosted-glass capsule.
    case frostedGlass
    /// Nothing when idle; bare-waveform look while a dictation is active.
    case hidden

    static let `default` = PillStyle.bareWaveform

    /// Maps any stored/legacy raw value to a current style. The retired styles
    /// (classic, dot, compact) and any unknown/missing value collapse into the
    /// default; "hidden" is preserved.
    init(migrating raw: String?) {
        switch raw {
        case PillStyle.bareWaveform.rawValue: self = .bareWaveform
        case PillStyle.dynamicIsland.rawValue: self = .dynamicIsland
        case PillStyle.frostedGlass.rawValue: self = .frostedGlass
        case PillStyle.hidden.rawValue: self = .hidden
        default: self = .default // classic / dot / compact / nil / anything else
        }
    }
}
