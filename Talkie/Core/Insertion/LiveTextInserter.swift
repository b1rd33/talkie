import AppKit
import ApplicationServices
import Carbon.HIToolbox

enum LiveTextFinalization: Equatable {
    case exact(route: DeliveryRoute, verification: DeliveryVerification, revisionCount: Int)
    case repaired(route: DeliveryRoute, verification: DeliveryVerification, revisionCount: Int)
    case clipboardFallback(reason: String, revisionCount: Int)
}

/// An ephemeral handle to the editable range Talkie owns for one dictation.
/// Implementations must verify both target identity and the existing owned text
/// before replacing it. A false result is terminal for the session: callers must
/// not guess with delete/backspace events.
@MainActor
protocol LiveTextOwnedRangeReplacing: AnyObject {
    func begin(targetBundleID: String?) -> Bool
    func replace(expected: String, with replacement: String) -> Bool
    func reset()
}

/// Captures the focused AX element and a zero-length insertion range. Every
/// replacement revalidates the app, element, range contents and secure-input
/// state. Surrounding text is read only for the comparison and is never retained.
@MainActor
final class AXLiveTextOwnedRange: LiveTextOwnedRangeReplacing {
    private var element: AXUIElement?
    private var range = CFRange()
    private var targetBundleID: String?

    func begin(targetBundleID: String?) -> Bool {
        reset()
        guard AXIsProcessTrusted(), !IsSecureEventInputEnabled(),
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == targetBundleID,
              let focused = Self.focusedElement(),
              Self.stringAttribute(kAXSubroleAttribute, element: focused) != kAXSecureTextFieldSubrole,
              let selectedRange = Self.rangeAttribute(element: focused),
              selectedRange.length == 0,
              Self.stringAttribute(kAXValueAttribute, element: focused) != nil else { return false }
        element = focused
        range = selectedRange
        self.targetBundleID = targetBundleID
        return true
    }

    func replace(expected: String, with replacement: String) -> Bool {
        guard !IsSecureEventInputEnabled(),
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == targetBundleID,
              let element,
              let focused = Self.focusedElement(),
              CFEqual(element, focused),
              let value = Self.stringAttribute(kAXValueAttribute, element: element),
              Self.substring(value, utf16Range: range) == expected else { return false }

        var ownedRange = range
        guard let axRange = AXValueCreate(.cfRange, &ownedRange),
              AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString,
                                           axRange) == .success,
              AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString,
                                           replacement as CFString) == .success else { return false }
        range.length = replacement.utf16.count
        guard let updated = Self.stringAttribute(kAXValueAttribute, element: element) else { return false }
        return Self.substring(updated, utf16Range: range) == replacement
    }

    func reset() {
        element = nil
        range = CFRange()
        targetBundleID = nil
    }

    private static func focusedElement() -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(),
                                            kAXFocusedUIElementAttribute as CFString,
                                            &value) == .success else { return nil }
        return value as! AXUIElement?
    }

    private static func rangeAttribute(element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString,
                                            &value) == .success,
              let axValue = value as! AXValue? else { return nil }
        var range = CFRange()
        return AXValueGetValue(axValue, .cfRange, &range) ? range : nil
    }

    private static func stringAttribute(_ attribute: String, element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }

    private static func substring(_ string: String, utf16Range: CFRange) -> String? {
        let utf16 = Array(string.utf16)
        guard utf16Range.location >= 0, utf16Range.length >= 0,
              utf16Range.location + utf16Range.length <= utf16.count else { return nil }
        return String(decoding: utf16[utf16Range.location..<(utf16Range.location + utf16Range.length)],
                      as: UTF16.self)
    }
}

@MainActor
protocol LiveTextInserting: AnyObject {
    func reset(targetBundleID: String?)
    @discardableResult func type(upTo accumulated: String) throws -> Bool
    func finalize(authoritative: String) throws -> LiveTextFinalization
    @discardableResult func eraseTyped() throws -> Bool
    var revisionCount: Int { get }
    var hasInsertedText: Bool { get }
}

extension LiveTextInserting {
    func reset() { reset(targetBundleID: nil) }
}

/// Streams text through an AX-owned range when possible. Hosts without a writable
/// range retain append-only Unicode events. A non-prefix revision on that fallback
/// is never repaired with blind backspaces; final text is copied instead.
@MainActor
final class LiveTextInserter: LiveTextInserting {
    private let secureInputCheck: () -> Bool
    private let axTrustedCheck: () -> Bool
    private let postUnicode: (String) -> Bool
    private let ownedRange: LiveTextOwnedRangeReplacing
    private var usesOwnedRange = false
    private var ownershipLost = false
    private var reconciliationRequired = false
    private var committed = ""
    private(set) var revisionCount = 0
    var hasInsertedText: Bool { !committed.isEmpty }

    init(secureInputCheck: @escaping () -> Bool = { IsSecureEventInputEnabled() },
         axTrustedCheck: @escaping () -> Bool = { AXIsProcessTrusted() },
         postUnicode: ((String) -> Bool)? = nil,
         ownedRange: LiveTextOwnedRangeReplacing? = nil) {
        self.secureInputCheck = secureInputCheck
        self.axTrustedCheck = axTrustedCheck
        self.postUnicode = postUnicode ?? Self.postUnicodeString
        self.ownedRange = ownedRange ?? AXLiveTextOwnedRange()
    }

    func reset(targetBundleID: String?) {
        ownedRange.reset()
        committed = ""
        revisionCount = 0
        ownershipLost = false
        reconciliationRequired = false
        usesOwnedRange = ownedRange.begin(targetBundleID: targetBundleID)
    }

    @discardableResult
    func type(upTo accumulated: String) throws -> Bool {
        if secureInputCheck() { throw InsertionError.secureInputActive }
        guard axTrustedCheck(), !ownershipLost else { return false }
        let isRevision = !accumulated.hasPrefix(committed)
        if isRevision { revisionCount += 1 }

        if usesOwnedRange {
            guard ownedRange.replace(expected: committed, with: accumulated) else {
                ownershipLost = true
                reconciliationRequired = true
                return false
            }
            committed = accumulated
            return true
        }

        guard let add = Self.suffix(committed: committed, accumulated: accumulated) else {
            reconciliationRequired = true
            return true // viable for capture, but final delivery must fail closed
        }
        guard add.isEmpty || postUnicode(add) else {
            reconciliationRequired = true
            return false
        }
        committed = accumulated
        return true
    }

    func finalize(authoritative: String) throws -> LiveTextFinalization {
        if secureInputCheck() { throw InsertionError.secureInputActive }
        guard axTrustedCheck(), !ownershipLost else {
            return .clipboardFallback(reason: "live_text_ownership_lost",
                                      revisionCount: revisionCount)
        }
        let neededRepair = revisionCount > 0 || reconciliationRequired || authoritative != committed
        guard try type(upTo: authoritative) else {
            return .clipboardFallback(reason: "live_text_final_reconciliation_failed",
                                      revisionCount: revisionCount)
        }
        guard !reconciliationRequired else {
            return .clipboardFallback(reason: "live_text_revision_unrepairable",
                                      revisionCount: revisionCount)
        }
        let route: DeliveryRoute = usesOwnedRange ? .accessibilityRange : .liveUnicodeEvents
        let verification: DeliveryVerification = usesOwnedRange ? .verified : .unverified
        return neededRepair
            ? .repaired(route: route, verification: verification, revisionCount: revisionCount)
            : .exact(route: route, verification: verification, revisionCount: revisionCount)
    }

    @discardableResult
    func eraseTyped() throws -> Bool {
        if secureInputCheck() { throw InsertionError.secureInputActive }
        guard axTrustedCheck(), !ownershipLost, usesOwnedRange else { return false }
        guard ownedRange.replace(expected: committed, with: "") else {
            ownershipLost = true
            return false
        }
        committed = ""
        return true
    }

    static func suffix(committed: String, accumulated: String) -> String? {
        guard accumulated.hasPrefix(committed) else { return nil }
        return String(accumulated.dropFirst(committed.count))
    }

    private static func postUnicodeString(_ s: String) -> Bool {
        guard let src = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)
        else { return false }
        let chars = Array(s.utf16)
        down.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: chars)
        up.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: chars)
        down.flags = []
        up.flags = []
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
