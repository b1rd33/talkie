import ApplicationServices
import Carbon.HIToolbox
import Foundation

struct FocusedContext: Equatable, Sendable {
    let precedingText: String
    let followingText: String
    let selectedText: String?

    var cleanupContext: String {
        [precedingText, selectedText, followingText]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " ⟦CURSOR⟧ ")
    }

    static func bounded(value: String, cursorUTF16Offset: Int, selection: String?,
                        surroundingLimit: Int = 500) -> FocusedContext? {
        let utf16 = Array(value.utf16)
        let cursor = min(max(0, cursorUTF16Offset), utf16.count)
        let before = String(decoding: utf16[max(0, cursor - surroundingLimit)..<cursor], as: UTF16.self)
        let after = String(decoding: utf16[cursor..<min(utf16.count, cursor + surroundingLimit)], as: UTF16.self)
        let boundedSelection = selection.map { String($0.prefix(8_000)) }
        guard !before.isEmpty || !after.isEmpty || boundedSelection?.isEmpty == false else { return nil }
        return FocusedContext(precedingText: before, followingText: after,
                              selectedText: boundedSelection)
    }
}

enum ContextPolicy {
    static func mayRead(enabled: Bool, bundleID: String?, exclusions: [String]) -> Bool {
        enabled && bundleID.map { !exclusions.contains($0) } != false
    }
}

@MainActor
protocol FocusedContextReading: AnyObject {
    func read() -> FocusedContext?
}

/// Reads only the focused editable element. Values are returned to the active
/// dictation and are never retained by this service.
@MainActor
final class FocusedContextReader: FocusedContextReading {
    func read() -> FocusedContext? {
        guard AXIsProcessTrusted(), !IsSecureEventInputEnabled() else { return nil }
        let system = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            system, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
              let element = focusedValue as! AXUIElement? else { return nil }

        if stringAttribute(kAXSubroleAttribute, element: element) == kAXSecureTextFieldSubrole {
            return nil
        }
        guard let value = stringAttribute(kAXValueAttribute, element: element) else { return nil }
        let selection = stringAttribute(kAXSelectedTextAttribute, element: element)
        var rangeValue: CFTypeRef?
        var cursor = value.utf16.count
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString,
                                         &rangeValue) == .success,
           let axRange = rangeValue as! AXValue? {
            var range = CFRange()
            if AXValueGetValue(axRange, .cfRange, &range) { cursor = range.location }
        }
        return FocusedContext.bounded(value: value, cursorUTF16Offset: cursor,
                                      selection: selection)
    }

    private func stringAttribute(_ attribute: String, element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }
}
