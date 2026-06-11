import AppKit

/// Watches the Esc key (keyCode 53) globally. Started only while a dictation is
/// active, stopped when idle — wired by AppServices via observation tracking.
@MainActor
final class EscKeyMonitor {
    var onEsc: () -> Void = {}
    private var globalMonitor: Any?
    private var localMonitor: Any?

    var isRunning: Bool { globalMonitor != nil }

    func start() {
        guard globalMonitor == nil else { return }
        let handler: (NSEvent) -> Void = { [weak self] event in
            guard event.keyCode == 53 else { return }
            DispatchQueue.main.async { self?.onEsc() }
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: handler)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
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
