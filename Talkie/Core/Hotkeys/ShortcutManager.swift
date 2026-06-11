import AppKit
import Foundation
import HotKey

/// A user-recorded shortcut, persisted as "cmd+shift+d"-style storage strings.
/// Bare letter/number keys are rejected (they'd swallow normal typing);
/// F-keys (F1–F20) are allowed modifier-free.
struct ShortcutSpec: Equatable {
    let key: Key
    let modifiers: NSEvent.ModifierFlags
    let storage: String

    init?(storage: String) {
        let parts = storage.lowercased().split(separator: "+").map(String.init)
        guard let keyPart = parts.last, let key = Key(string: keyPart) else { return nil }
        var modifiers: NSEvent.ModifierFlags = []
        for part in parts.dropLast() {
            switch part {
            case "cmd": modifiers.insert(.command)
            case "shift": modifiers.insert(.shift)
            case "opt": modifiers.insert(.option)
            case "ctrl": modifiers.insert(.control)
            default: return nil
            }
        }
        let isFKey = keyPart.hasPrefix("f") && Int(keyPart.dropFirst()) != nil
        guard !modifiers.isEmpty || isFKey else { return nil }
        self.key = key
        self.modifiers = modifiers
        self.storage = storage.lowercased()
    }

    init?(key: Key, modifiers: NSEvent.ModifierFlags) {
        var parts: [String] = []
        if modifiers.contains(.command) { parts.append("cmd") }
        if modifiers.contains(.shift) { parts.append("shift") }
        if modifiers.contains(.option) { parts.append("opt") }
        if modifiers.contains(.control) { parts.append("ctrl") }
        parts.append(key.description.lowercased())
        self.init(storage: parts.joined(separator: "+"))
    }

    var display: String {
        var text = ""
        if modifiers.contains(.command) { text += "⌘" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.control) { text += "⌃" }
        // HotKey prefixes F-key descriptions with a private-use glyph (U+F861-ish);
        // strip PUA scalars so the display reads "F13", not "<?>F13".
        let keyText = String(String.UnicodeScalarView(
            key.description.unicodeScalars.filter { !(0xE000...0xF8FF).contains($0.value) }))
        return text + keyText.uppercased()
    }
}

/// Owns HotKey-backed global shortcuts. Phase 2: paste-last (⇧⌥V).
/// Phase 4: user-customizable push-to-talk and hands-free combos.
@MainActor
final class ShortcutManager {
    private var pasteLastHotKey: HotKey?
    private var pttHotKey: HotKey?
    private var handsFreeHotKey: HotKey?

    func enablePasteLast(_ action: @escaping () -> Void) {
        pasteLastHotKey = HotKey(key: .v, modifiers: [.shift, .option])
        pasteLastHotKey?.keyDownHandler = action
    }

    /// Rebinds the push-to-talk combo (nil clears it). Hold = record, release = process.
    func bindPushToTalk(_ spec: ShortcutSpec?, onPress: @escaping () -> Void, onRelease: @escaping () -> Void) {
        pttHotKey = nil
        guard let spec else { return }
        let hotKey = HotKey(key: spec.key, modifiers: spec.modifiers)
        hotKey.keyDownHandler = onPress
        hotKey.keyUpHandler = onRelease
        pttHotKey = hotKey
    }

    /// Rebinds the hands-free toggle combo (nil clears it).
    func bindHandsFree(_ spec: ShortcutSpec?, onToggle: @escaping () -> Void) {
        handsFreeHotKey = nil
        guard let spec else { return }
        let hotKey = HotKey(key: spec.key, modifiers: spec.modifiers)
        hotKey.keyDownHandler = onToggle
        handsFreeHotKey = hotKey
    }
}
