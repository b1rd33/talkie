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
    static func shouldShowPanel(state: DictationState, style: String,
                                showFlowBar: Bool, recentlyCompleted: Bool) -> Bool {
        guard showFlowBar else { return false }
        switch style {
        case "hidden", "compact":
            return state != .idle || recentlyCompleted
        default: // classic, dot — always present
            return true
        }
    }

    /// Should the panel participate in hit-testing?
    /// Only when something is clickable: the active pill's ✕ / context menu,
    /// or classic's idle hover-mic + right-click menu.
    static func shouldAcceptMouse(state: DictationState, style: String) -> Bool {
        if state != .idle { return true }
        return style == "classic"
    }
}
