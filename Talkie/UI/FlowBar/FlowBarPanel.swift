import AppKit
import SwiftUI

/// Always-on-top, never-key pill at bottom-center of the active screen (spec §7).
@MainActor
final class FlowBarPanel {
    private let panel: NSPanel

    init(coordinator: DictationCoordinator, recorder: AudioRecorder,
         onHideForHour: @escaping () -> Void = {},
         onHidePermanently: @escaping () -> Void = {}) {
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

        let host = NSHostingView(rootView: FlowBarView(coordinator: coordinator, recorder: recorder,
                                                       onHideForHour: onHideForHour,
                                                       onHidePermanently: onHidePermanently))
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

    private func reposition() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 12))
    }
}
