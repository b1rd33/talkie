import Foundation
import HotKey

/// Owns HotKey-backed global shortcuts. Phase 2: paste-last (⇧⌥V).
/// Phase 4 extends this with user-customizable recording shortcuts.
@MainActor
final class ShortcutManager {
    private var pasteLastHotKey: HotKey?

    func enablePasteLast(_ action: @escaping () -> Void) {
        pasteLastHotKey = HotKey(key: .v, modifiers: [.shift, .option])
        pasteLastHotKey?.keyDownHandler = action
    }
}
