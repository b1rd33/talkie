import Foundation

/// Immutable motion values for the production pill.
struct PillMotionProfile: Equatable, Sendable {
    var entryDuration: TimeInterval
    var entryMinimumScale: Double
    var handsFreeDuration: TimeInterval
    var handsFreeMinimumScale: Double
    var handsFreeMaximumScale: Double
    var processingRotationDuration: TimeInterval
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
        processingRotationDuration: 0.9,
        successDuration: 0.16,
        completionPanelDuration: 0.18,
        waveformFPS: 30,
        animatesWaveformGeometry: true)

    static let minimalMotion = Self(
        entryDuration: 0.12,
        entryMinimumScale: 1,
        handsFreeDuration: 0,
        handsFreeMinimumScale: 1,
        handsFreeMaximumScale: 1,
        // A progress indicator must still communicate ongoing work when macOS
        // Reduce Motion is enabled. Keep it moving, but at half speed.
        processingRotationDuration: 1.8,
        successDuration: 0.16,
        completionPanelDuration: 0.18,
        waveformFPS: 8,
        animatesWaveformGeometry: false)

    static func resolve(reduceMotion: Bool) -> Self {
        reduceMotion ? .minimalMotion : .calmFlow
    }

    func processingRotationDegrees(at time: TimeInterval) -> Double {
        guard processingRotationDuration > 0 else { return 0 }
        let position = time.truncatingRemainder(dividingBy: processingRotationDuration)
        return position / processingRotationDuration * 360
    }
}
