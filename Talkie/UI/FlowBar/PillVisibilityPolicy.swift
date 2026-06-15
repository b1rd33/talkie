import Foundation

/// Pure decision logic for the Flow Bar panel's existence and mouse participation.
///
/// Crash 2026-06-11 (`EXC_BAD_ACCESS` in SwiftUI hit-testing): an idle panel in
/// the "hidden" style hosted a degenerate invisible view tree but still accepted
/// mouse events — hit-testing it crashed deep in `NSViewResponder.platformCurrentEvent`.
/// The fix is structural: when there is nothing to see or click, the panel is
/// ordered OUT and mouse events are ignored, so AppKit never hit-tests it.
enum PillVisibilityPolicy {
    /// Should the panel be on screen at all?
    /// hidden/compact styles exist only while a dictation is active (plus the
    /// ~1s green-checkmark flash right after completion).
    static func shouldShowPanel(state: DictationState, style: PillStyle,
                                showFlowBar: Bool, recentlyCompleted: Bool) -> Bool {
        guard showFlowBar else { return false }
        switch style {
        case .hidden:
            return state != .idle || recentlyCompleted
        default: // bareWaveform, dynamicIsland, frostedGlass — always present
            return true
        }
    }

    /// Should the panel participate in hit-testing?
    /// Only while active (the pill's ✕ / context menu). At idle the redesigned
    /// pill is a calm, click-through indicator — ignoring the mouse there also
    /// keeps AppKit from ever hit-testing it (the 2026-06-11 crash was an idle
    /// hit-test of a degenerate view).
    static func shouldAcceptMouse(state: DictationState, style: PillStyle) -> Bool {
        state != .idle
    }
}
