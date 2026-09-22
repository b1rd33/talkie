import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Retains only field identity, never the field's text. Synthetic input must
/// revalidate it after every suspension, immediately before posting an event.
@MainActor
enum FocusedInputTarget {
    static func capture(bundleID: String?) -> (() -> Bool)? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              bundleID == nil || app.bundleIdentifier == bundleID,
              let element = focusedElement(), !IsSecureEventInputEnabled() else { return nil }
        var subrole: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
        guard subrole as? String != kAXSecureTextFieldSubrole else { return nil }
        let pid = app.processIdentifier
        return {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                  !IsSecureEventInputEnabled(), let current = focusedElement() else { return false }
            return CFEqual(element, current)
        }
    }

    private static func focusedElement() -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(),
                                            kAXFocusedUIElementAttribute as CFString,
                                            &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
}
