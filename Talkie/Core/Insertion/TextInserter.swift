import AppKit
import Carbon.HIToolbox

@MainActor
protocol TextInserting: AnyObject {
    func insert(_ text: String) async throws
}

/// Inserts text into the frontmost app: pasteboard write + synthetic ⌘V (spec §5).
/// Phase 2 adds pasteboard snapshot/restore and the secure-input guard.
@MainActor
final class TextInserter: TextInserting {
    /// Injectable so tests don't post real keystrokes.
    private let pasteKeystroke: () -> Void

    init(pasteKeystroke: (() -> Void)? = nil) {
        self.pasteKeystroke = pasteKeystroke ?? Self.postCmdV
    }

    func insert(_ text: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(trimmed, forType: .string)
        // Give the pasteboard server a beat before the keystroke lands.
        try await Task.sleep(for: .milliseconds(50))
        pasteKeystroke()
    }

    private static func postCmdV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
