import AppKit
import SwiftUI

/// Always-on-top, never-key pill at bottom-center of the active screen (spec §7).
@MainActor
final class FlowBarPanel {
    private let panel: NSPanel
    private let settings: SettingsStore?

    init(coordinator: DictationCoordinator, recorder: AudioRecorder,
         settings: SettingsStore? = nil,
         onHideForHour: @escaping () -> Void = {},
         onHidePermanently: @escaping () -> Void = {}) {
        self.settings = settings
        panel = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false // pill has click targets now (✕, context menu)
        panel.hidesOnDeactivate = false

        let root = FlowBarView(coordinator: coordinator, recorder: recorder,
                               onHideForHour: onHideForHour,
                               onHidePermanently: onHidePermanently)
        // .environment makes SettingsStore observable INSIDE the hosting view —
        // pill style/engine badge updates require it (see FlowBarView.settings).
        let host = settings.map { NSHostingView(rootView: AnyView(root.environment($0))) }
            ?? NSHostingView(rootView: AnyView(root))
        host.frame = NSRect(x: 0, y: 0, width: 260, height: 56)
        panel.contentView = host
        panel.setContentSize(host.frame.size)
        reposition()
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reposition() }
        }
    }

    func setVisible(_ visible: Bool) {
        visible ? panel.orderFrontRegardless() : panel.orderOut(nil)
    }

    /// Applies PillVisibilityPolicy for the current dictation state: orders the
    /// panel in/out and gates mouse participation so an idle, invisible pill is
    /// never hit-tested (crash 2026-06-11).
    func applyActivity(state: DictationState, recentlyCompleted: Bool) {
        let style = settings?.pillStyle ?? "classic"
        let show = PillVisibilityPolicy.shouldShowPanel(
            state: state, style: style,
            showFlowBar: settings?.showFlowBar ?? true,
            recentlyCompleted: recentlyCompleted)
        panel.ignoresMouseEvents = !PillVisibilityPolicy.shouldAcceptMouse(state: state, style: style)
        setVisible(show)
    }

    /// Re-reads Settings → pill position and moves the panel (AppServices tracks changes).
    func reposition() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        let margin: CGFloat = 12
        let origin: NSPoint
        switch settings?.pillPosition ?? "bottomCenter" {
        case "bottomLeft":
            origin = NSPoint(x: frame.minX + margin, y: frame.minY + margin)
        case "bottomRight":
            origin = NSPoint(x: frame.maxX - size.width - margin, y: frame.minY + margin)
        case "topCenter":
            origin = NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height - margin)
        default: // bottomCenter
            origin = NSPoint(x: frame.midX - size.width / 2, y: frame.minY + margin)
        }
        panel.setFrameOrigin(origin)
    }
}
