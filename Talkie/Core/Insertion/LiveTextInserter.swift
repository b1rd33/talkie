import AppKit
import Carbon.HIToolbox

/// Types streamed text into the focused app incrementally (instant live typing).
/// Unlike `TextInserter` (clipboard snapshot + one ⌘V), this posts the *newly
/// appended* characters as Unicode key events as the transcript grows.
@MainActor
protocol LiveTextInserting: AnyObject {
    func reset()
    /// Type whatever `accumulated` adds beyond what's already been typed.
    /// Returns true if typing is viable (Accessibility granted); false means the
    /// caller should fall back to a normal end-of-dictation insert. Throws on a
    /// secure-input field (never type into password fields).
    @discardableResult
    func type(upTo accumulated: String) throws -> Bool
    /// Erase everything typed so far this dictation (one backspace per character)
    /// and reset. Used to replace live-typed raw text with a cleaned version on
    /// release. Returns true if viable (Accessibility granted); throws on a secure field.
    @discardableResult
    func eraseTyped() throws -> Bool
}

@MainActor
final class LiveTextInserter: LiveTextInserting {
    private let secureInputCheck: () -> Bool
    private let axTrustedCheck: () -> Bool
    private let postUnicode: (String) -> Bool
    /// Everything already typed this dictation. Tracked as a String so suffix
    /// diffing stays grapheme-safe (never splits an emoji).
    private var committed = ""

    init(secureInputCheck: @escaping () -> Bool = { IsSecureEventInputEnabled() },
         axTrustedCheck: @escaping () -> Bool = { AXIsProcessTrusted() },
         postUnicode: ((String) -> Bool)? = nil) {
        self.secureInputCheck = secureInputCheck
        self.axTrustedCheck = axTrustedCheck
        self.postUnicode = postUnicode ?? Self.postUnicodeString
    }

    func reset() { committed = "" }

    @discardableResult
    func eraseTyped() throws -> Bool {
        if secureInputCheck() { throw InsertionError.secureInputActive }
        guard axTrustedCheck() else { return false } // can't post events without AX trust
        for _ in 0..<committed.count { _ = Self.postBackspace() }
        committed = ""
        return true
    }

    @discardableResult
    func type(upTo accumulated: String) throws -> Bool {
        if secureInputCheck() { throw InsertionError.secureInputActive }
        guard axTrustedCheck() else { return false } // can't post events without AX trust
        guard let add = Self.suffix(committed: committed, accumulated: accumulated) else {
            return true // non-prefix revision: skip this emission, stay viable
        }
        if !add.isEmpty { _ = postUnicode(add) }
        committed = accumulated
        return true
    }

    /// The characters `accumulated` adds beyond `committed`, or nil when
    /// `accumulated` is not a prefix-extension of `committed` (a revision).
    /// Grapheme-safe: prefix/drop operate on Characters.
    static func suffix(committed: String, accumulated: String) -> String? {
        guard accumulated.hasPrefix(committed) else { return nil }
        return String(accumulated.dropFirst(committed.count))
    }

    /// Posts a single Backspace (delete-left) keystroke to the focused app.
    private static func postBackspace() -> Bool {
        guard let src = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_Delete), keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_Delete), keyDown: false)
        else { return false }
        down.flags = []
        up.flags = []
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    /// Posts a string as a single Unicode key event to the focused app.
    private static func postUnicodeString(_ s: String) -> Bool {
        guard let src = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)
        else { return false }
        let chars = Array(s.utf16)
        down.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: chars)
        up.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: chars)
        // Clear modifier flags before posting. Push-to-talk holds fn while live text
        // streams DURING the hold, and CGEventSource(.combinedSessionState) carries
        // that held fn (or any modifier) into the synthetic event — sending fn+char,
        // which apps don't insert as text and which pokes the Dock/Finder. TextInserter's
        // ⌘V path sets flags explicitly for the same reason; mirror it here.
        down.flags = []
        up.flags = []
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
