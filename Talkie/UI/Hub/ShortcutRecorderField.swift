import SwiftUI
import HotKey

/// Click-to-record shortcut capture. NSViewRepresentable because SwiftUI has no
/// raw keyDown capture; the view becomes first responder and swallows one combo.
struct ShortcutRecorderField: NSViewRepresentable {
    @Binding var storage: String?   // ShortcutSpec.storage, nil = unset

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onCapture = { storage = $0 }
        return view
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.currentDisplay = storage.flatMap { ShortcutSpec(storage: $0)?.display }
    }

    final class RecorderView: NSView {
        var onCapture: ((String?) -> Void)?
        var currentDisplay: String? { didSet { needsDisplay = true } }
        private var recording = false { didSet { needsDisplay = true } }

        override var acceptsFirstResponder: Bool { true }
        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            recording = true
        }
        override func resignFirstResponder() -> Bool {
            recording = false
            return super.resignFirstResponder()
        }
        override func keyDown(with event: NSEvent) {
            guard recording else { return super.keyDown(with: event) }
            switch event.keyCode {
            case 53: recording = false                       // Esc cancels
            case 51: onCapture?(nil); recording = false      // ⌫ clears
            default:
                guard let key = Key(carbonKeyCode: UInt32(event.keyCode)),
                      let spec = ShortcutSpec(key: key, modifiers: event.modifierFlags
                          .intersection([.command, .shift, .option, .control])) else {
                    NSSound.beep(); return                   // rejected (e.g. bare letter)
                }
                onCapture?(spec.storage)
                recording = false
            }
        }
        override func draw(_ dirtyRect: NSRect) {
            let text = recording ? "Press a shortcut…" : (currentDisplay ?? "Click to record")
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: recording ? NSColor.controlAccentColor : .labelColor,
            ]
            NSColor.quaternaryLabelColor.setStroke()
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5)
            path.stroke()
            let size = text.size(withAttributes: attrs)
            text.draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                                  y: (bounds.height - size.height) / 2), withAttributes: attrs)
        }
        override var intrinsicContentSize: NSSize { NSSize(width: 160, height: 24) }
    }
}
