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

    /// True while we're discarding a startup `.function` replay. macOS delivers an
    /// initial flagsChanged reflecting the current modifier state right after the
    /// monitors install; if fn reads as down then — or a stray `.function` event
    /// arrives within the startup grace window — that down (and the release that
    /// settles it) are noise, not a real press. They once started a phantom
    /// dictation at launch (2026-06); the bug is racy, so we guard both the
    /// already-down case and the just-after-launch window.
    private var awaitingNeutral = false
    private var startedAt: Date?
    /// A real fn press can't physically happen this soon after the monitors
    /// install at launch, so any press inside this window is a replay.
    static let startupGrace: TimeInterval = 0.7

    /// Sample the current fn state when monitoring begins. If fn is already down,
    /// ignore events until the key settles back to neutral; either way, arm the
    /// startup grace window.
    func primeStartupState(fnDown: Bool, at now: Date = Date()) {
        startedAt = now
        if fnDown {
            isDown = true
            awaitingNeutral = true
        } else {
            isDown = false
            awaitingNeutral = false
        }
    }

    /// Pure transition logic, unit-testable without NSEvent.
    func handleFlagsChanged(fnDown: Bool, at now: Date = Date()) {
        guard fnDown != isDown else { return }
        if awaitingNeutral {
            // Still draining the startup replay; consume the settle-to-neutral
            // transition without firing or seeding double-tap state.
            isDown = fnDown
            if !fnDown {
                awaitingNeutral = false
                downAt = nil
                lastTapEndedAt = nil
            }
            return
        }
        // A press inside the startup grace window is a replay: swallow it and the
        // release that follows.
        if fnDown, let startedAt, now.timeIntervalSince(startedAt) < Self.startupGrace {
            isDown = true
            awaitingNeutral = true
            return
        }
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
        // Discard the startup replay if fn happens to be down as we attach.
        primeStartupState(fnDown: NSEvent.modifierFlags.contains(.function))
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
