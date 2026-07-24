import Foundation

/// Immutable motion values for the production pill.
struct PillMotionProfile: Equatable, Sendable {
    var entryDuration: TimeInterval
    var entryMinimumScale: Double
    var handsFreeDuration: TimeInterval
    var handsFreeMinimumScale: Double
    var handsFreeMaximumScale: Double
    var successDuration: TimeInterval
    var waveformFPS: Int
    var animatesWaveformGeometry: Bool

    static let calmFlow = Self(
        entryDuration: 0.35,
        entryMinimumScale: 0.65,
        handsFreeDuration: 2.4,
        handsFreeMinimumScale: 0.985,
        handsFreeMaximumScale: 1.015,
        successDuration: 0.8,
        waveformFPS: 30,
        animatesWaveformGeometry: true)

    static let minimalMotion = Self(
        entryDuration: 0.12,
        entryMinimumScale: 1,
        handsFreeDuration: 0,
        handsFreeMinimumScale: 1,
        handsFreeMaximumScale: 1,
        successDuration: 0.8,
        waveformFPS: 8,
        animatesWaveformGeometry: false)

    static func resolve(reduceMotion: Bool) -> Self {
        reduceMotion ? .minimalMotion : .calmFlow
    }
}
