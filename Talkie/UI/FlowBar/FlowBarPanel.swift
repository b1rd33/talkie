import AppKit
import SwiftUI

/// Always-on-top, never-key pill at bottom-center of the active screen (spec §7).
@MainActor
final class FlowBarPanel {
    private let panel: NSPanel
    private let settings: SettingsStore?
    private let host: NSHostingView<AnyView>
    private let makeRoot: () -> AnyView

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

        // .environment makes SettingsStore observable INSIDE the hosting view —
        // pill style/engine badge updates require it (see FlowBarView.settings).
        let makeRoot: () -> AnyView = {
            let root = FlowBarView(coordinator: coordinator, recorder: recorder,
                                   onHideForHour: onHideForHour,
                                   onHidePermanently: onHidePermanently)
            return settings.map { AnyView(root.environment($0)) } ?? AnyView(root)
        }
        self.makeRoot = makeRoot
        let host = NSHostingView(rootView: makeRoot())
        self.host = host
        // The pill is a fixed-size panel (PillLayout.panelSize). Empty sizing
        // options stop NSHostingView from driving the window size on rootView
        // reassignment — that resize zeroed the panel and broke positioning.
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: PillLayout.panelSize)
        panel.contentView = host
        reposition()
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reposition() }
        }
    }

    func setVisible(_ visible: Bool) {
        if visible {
            reposition() // re-assert size + origin before every show
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    /// Deterministic re-render: reassigning rootView forces NSHostingView to
    /// rebuild the body with the current pillStyle — no reliance on Observation
    /// reaching into the hosted tree (live-testing bug: style changes didn't render).
    func refreshStyle() {
        host.rootView = makeRoot()
        reposition()
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

    /// Re-reads Settings → pill position and moves the panel (AppServices tracks
    /// changes). Sets the full frame from PillLayout's constant size — never from
    /// panel.frame, which is transiently zero around rootView swaps.
    func reposition() {
        guard let screen = NSScreen.main else { return }
        let origin = PillLayout.origin(position: settings?.pillPosition ?? "bottomCenter",
                                       screenFrame: screen.visibleFrame)
        panel.setFrame(NSRect(origin: origin, size: PillLayout.panelSize), display: true)
    }
}
