import AppKit
import Carbon.HIToolbox

enum InsertionError: Error, Equatable, LocalizedError {
    case secureInputActive

    var errorDescription: String? {
        switch self {
        case .secureInputActive: "Password field — Talkie won't insert here."
        }
    }
}

@MainActor
protocol TextInserting: AnyObject {
    func insert(_ text: String) async throws
}

/// Inserts text into the frontmost app (spec §5), tiered:
/// 1. secure input active → refuse + notify
/// 2. no Accessibility trust → clipboard-only fallback + notify
/// 3. normal: snapshot pasteboard → write → synthetic ⌘V → restore-if-unchanged
///    (a failed ⌘V post keeps the transcript on the clipboard + notifies, spec §10)
@MainActor
final class TextInserter: TextInserting {
    private let pasteKeystroke: () -> Bool
    private let secureInputCheck: () -> Bool
    private let axTrustedCheck: () -> Bool
    private let notifier: Notifying?
    private let restoreDelay: Duration
    private let pasteboardGuard = PasteboardGuard()

    init(pasteKeystroke: (() -> Bool)? = nil,
         secureInputCheck: @escaping () -> Bool = { IsSecureEventInputEnabled() },
         axTrustedCheck: @escaping () -> Bool = { AXIsProcessTrusted() },
         notifier: Notifying? = nil,
         restoreDelay: Duration = .milliseconds(300)) {
        self.pasteKeystroke = pasteKeystroke ?? Self.postCmdV
        self.secureInputCheck = secureInputCheck
        self.axTrustedCheck = axTrustedCheck
        self.notifier = notifier
        self.restoreDelay = restoreDelay
    }

    func insert(_ text: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if secureInputCheck() {
            notifier?.notify(title: "Password field", body: "Talkie never types into secure fields.")
            throw InsertionError.secureInputActive
        }
        guard axTrustedCheck() else {
            // Without Accessibility we can't post the keystroke — leave it on the
            // clipboard (no restore: the user needs it there) and tell them.
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(trimmed, forType: .string)
            notifier?.notify(title: "Copied — press ⌘V",
                             body: "Grant Accessibility in System Settings for automatic insertion.")
            return
        }

        pasteboardGuard.snapshotAndWrite(trimmed)
        try await Task.sleep(for: .milliseconds(50)) // let the pasteboard server settle
        guard pasteKeystroke() else {
            // ⌘V couldn't be posted (spec §10 "paste failure"): keep the transcript on
            // the clipboard — no restore, the user needs it there — and tell them.
            notifier?.notify(title: "Copied — press ⌘V",
                             body: "Talkie couldn't send the paste keystroke.")
            return
        }
        try await Task.sleep(for: restoreDelay) // let the target app read it
        pasteboardGuard.restoreIfUnchanged()
    }

    private static func postCmdV() -> Bool {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
