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
    func insert(_ text: String, targetBundleID: String?) async throws -> DeliveryOutcome
    /// Leave text on the clipboard and notify, without posting any keystroke — used
    /// when the press-time target app is no longer focused, so a paste/erase can never
    /// land in the wrong app.
    func copyToClipboard(_ text: String, targetBundleID: String?) -> DeliveryOutcome
    /// Best-effort Return key action. Implementations must independently verify that
    /// synthetic input is safe before posting it.
    func pressEnter() -> Bool
    func undo() -> Bool
}

extension TextInserting {
    func insert(_ text: String) async throws -> DeliveryOutcome {
        try await insert(text, targetBundleID: nil)
    }

    func copyToClipboard(_ text: String) -> DeliveryOutcome {
        copyToClipboard(text, targetBundleID: nil)
    }

    func pressEnter() -> Bool { false }
    func undo() -> Bool { false }
}

/// Inserts text into the frontmost app (spec §5), tiered:
/// 1. secure input active → refuse + notify
/// 2. no Accessibility trust → clipboard-only fallback + notify
/// 3. normal: snapshot pasteboard → write → synthetic ⌘V → restore-if-unchanged
///    (a failed ⌘V post keeps the transcript on the clipboard + notifies, spec §10)
@MainActor
final class TextInserter: TextInserting {
    private let pasteKeystroke: () -> Bool
    private let enterKeystroke: () -> Bool
    private let undoKeystroke: () -> Bool
    private let secureInputCheck: () -> Bool
    private let axTrustedCheck: () -> Bool
    private let notifier: Notifying?
    private let restoreDelay: Duration
    private let pasteboardGuard: PasteboardGuarding

    init(pasteKeystroke: (() -> Bool)? = nil,
         enterKeystroke: (() -> Bool)? = nil,
         undoKeystroke: (() -> Bool)? = nil,
         secureInputCheck: @escaping () -> Bool = { IsSecureEventInputEnabled() },
         axTrustedCheck: @escaping () -> Bool = { AXIsProcessTrusted() },
         notifier: Notifying? = nil,
         pasteboardGuard: PasteboardGuarding? = nil,
         restoreDelay: Duration = .milliseconds(300)) {
        self.pasteKeystroke = pasteKeystroke ?? Self.postCmdV
        self.enterKeystroke = enterKeystroke ?? { Self.postKey(CGKeyCode(kVK_Return)) }
        self.undoKeystroke = undoKeystroke ?? Self.postCmdZ
        self.secureInputCheck = secureInputCheck
        self.axTrustedCheck = axTrustedCheck
        self.notifier = notifier
        self.pasteboardGuard = pasteboardGuard ?? PasteboardGuard()
        self.restoreDelay = restoreDelay
    }

    func insert(_ text: String, targetBundleID: String?) async throws -> DeliveryOutcome {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return DeliveryOutcome(
                route: .refused,
                verification: .failed,
                targetBundleID: targetBundleID,
                fallbackReason: "empty_text")
        }

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
                             body: "Grant Accessibility in System Settings for automatic insertion.",
                             destination: .accessibility)
            return DeliveryOutcome(
                route: .clipboardOnly,
                verification: .unverified,
                targetBundleID: targetBundleID,
                fallbackReason: "accessibility_unavailable")
        }

        pasteboardGuard.snapshotAndWrite(trimmed)
        try await Task.sleep(for: .milliseconds(50)) // let the pasteboard server settle
        guard pasteKeystroke() else {
            // ⌘V couldn't be posted (spec §10 "paste failure"): keep the transcript on
            // the clipboard — no restore, the user needs it there — and tell them.
            notifier?.notify(title: "Copied — press ⌘V",
                             body: "Talkie couldn't send the paste keystroke.")
            return DeliveryOutcome(
                route: .clipboardOnly,
                verification: .unverified,
                targetBundleID: targetBundleID,
                fallbackReason: "paste_keystroke_failed")
        }
        try await Task.sleep(for: restoreDelay) // let the target app read it
        pasteboardGuard.restoreIfUnchanged()
        return DeliveryOutcome(
            route: .clipboardPaste,
            verification: .unverified,
            targetBundleID: targetBundleID)
    }

    func copyToClipboard(_ text: String, targetBundleID: String?) -> DeliveryOutcome {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return DeliveryOutcome(
                route: .refused,
                verification: .failed,
                targetBundleID: targetBundleID,
                fallbackReason: "empty_text")
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(trimmed, forType: .string)
        notifier?.notify(title: "Copied — press ⌘V",
                         body: "You switched apps mid-dictation — the text is on your clipboard.")
        return DeliveryOutcome(
            route: .clipboardOnly,
            verification: .unverified,
            targetBundleID: targetBundleID,
            fallbackReason: "target_not_frontmost")
    }

    func pressEnter() -> Bool {
        guard !secureInputCheck(), axTrustedCheck() else { return false }
        return enterKeystroke()
    }

    func undo() -> Bool {
        guard !secureInputCheck(), axTrustedCheck() else { return false }
        return undoKeystroke()
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

    private static func postCmdZ() -> Bool {
        let source = CGEventSource(stateID: .combinedSessionState)
        let key = CGKeyCode(kVK_ANSI_Z)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else { return false }
        down.flags = .maskCommand; up.flags = .maskCommand
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        return true
    }

    private static func postKey(_ key: CGKeyCode) -> Bool {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        else { return false }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
