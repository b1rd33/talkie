import AppKit

/// Watches the bare `fn` key globally via flagsChanged events.
/// Requires Accessibility permission for the global monitor; a local monitor
/// covers the case where Talkie's own windows have focus.
@MainActor
final class FnKeyMonitor {
    var onPress: () -> Void = {}
    var onRelease: () -> Void = {}

    private(set) var isDown = false
    private var globalMonitor: Any?
    private var localMonitor: Any?

    var onDoubleTap: () -> Void = {}

    private var downAt: Date?
    private var lastTapEndedAt: Date?
    static let tapMaxHold: TimeInterval = 0.3
    static let doubleTapWindow: TimeInterval = 0.45

    /// Pure transition logic, unit-testable without NSEvent.
    func handleFlagsChanged(fnDown: Bool, at now: Date = Date()) {
        guard fnDown != isDown else { return }
        isDown = fnDown
        if fnDown {
            downAt = now
            onPress()
        } else {
            onRelease()
            let wasTap = now.timeIntervalSince(downAt ?? now) < Self.tapMaxHold
            if wasTap {
                if let last = lastTapEndedAt, now.timeIntervalSince(last) < Self.doubleTapWindow {
                    lastTapEndedAt = nil
                    onDoubleTap()
                } else {
                    lastTapEndedAt = now
                }
            } else {
                lastTapEndedAt = nil
            }
        }
    }

    func start() {
        guard globalMonitor == nil else { return }
        let handler: (NSEvent) -> Void = { [weak self] event in
            let fnDown = event.modifierFlags.contains(.function)
            // Main queue is strictly FIFO — preserves down/up ordering, unlike unstructured Tasks.
            DispatchQueue.main.async { self?.handleFlagsChanged(fnDown: fnDown) }
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: handler)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            handler(event)
            return event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }
}
