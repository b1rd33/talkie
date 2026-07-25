#if DEBUG
import AppKit
import SwiftUI

/// Isolated native UI fixture for documentation screenshots.
///
/// This uses the production pill renderer with synthetic audio levels. It never
/// starts the recorder, permission checks, global shortcuts, provider clients,
/// or the user's persistent history/defaults/keychain domains.
@MainActor
final class ScreenshotDemoPillPanel {
    private let panel: NSPanel
    private let levelSource = SimulatedAudioLevelSource(seed: 42, fixture: .energetic)
    private let canvasSize = NSSize(width: 320, height: 88)

    init() {
        // Seed the production renderer with a strong, deterministic voice frame.
        levelSource.frame = 42
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: canvasSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.setAccessibilityLabel("Talkie screenshot demo — active organic pill")

        let presentation = PillPresentation(
            state: .recording(handsFree: false),
            style: .calmFlowRibbon,
            elapsed: 4,
            audioLevel: 1,
            errorMessage: nil,
            offline: false,
            cleanupDegraded: false,
            reduceMotion: false,
            increasedContrast: true,
            isInstant: false)
        let root = ZStack {
            Color(red: 0.08, green: 0.09, blue: 0.12)
            PillRendererView(
                presentation: presentation,
                levelSource: levelSource,
                recordingStartedAt: nil)
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: canvasSize)
        panel.contentView = host

        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let origin = CGPoint(
            x: screen.visibleFrame.midX - canvasSize.width / 2,
            y: screen.visibleFrame.maxY - canvasSize.height - PillLayout.margin)
        panel.setFrame(NSRect(origin: origin, size: canvasSize), display: true)
        panel.orderFrontRegardless()
    }
}
#endif
