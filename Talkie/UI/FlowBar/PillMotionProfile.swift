import Foundation

/// Immutable motion values for the production pill.
struct PillMotionProfile: Equatable, Sendable {
    var entryDuration: TimeInterval
    var entryMinimumScale: Double
    var handsFreeDuration: TimeInterval
    var handsFreeMinimumScale: Double
    var handsFreeMaximumScale: Double
    var processingLabelDelay: TimeInterval
    var successDuration: TimeInterval
    var completionPanelDuration: TimeInterval
    var waveformFPS: Int
    var animatesWaveformGeometry: Bool

    static let calmFlow = Self(
        entryDuration: 0.18,
        entryMinimumScale: 0.92,
        handsFreeDuration: 2.4,
        handsFreeMinimumScale: 0.985,
        handsFreeMaximumScale: 1.015,
        processingLabelDelay: 0.65,
        successDuration: 0.4,
        completionPanelDuration: 0.6,
        waveformFPS: 30,
        animatesWaveformGeometry: true)

    static let minimalMotion = Self(
        entryDuration: 0.12,
        entryMinimumScale: 1,
        handsFreeDuration: 0,
        handsFreeMinimumScale: 1,
        handsFreeMaximumScale: 1,
        processingLabelDelay: 0.65,
        successDuration: 0.4,
        completionPanelDuration: 0.6,
        waveformFPS: 8,
        animatesWaveformGeometry: false)

    static func resolve(reduceMotion: Bool) -> Self {
        reduceMotion ? .minimalMotion : .calmFlow
    }
}
