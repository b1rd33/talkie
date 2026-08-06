import AppKit
import SwiftUI
import XCTest
@testable import Talkie

@MainActor
final class PillRenderingTests: XCTestCase {
    private final class MutableLevelSource: AudioLevelReading {
        var latestLevel: Float

        init(level: Float) {
            latestLevel = level
        }
    }

    func testEveryStateAndVisibleStyleProducesNonEmptyNativePixels() throws {
        let states: [PillPresentation.State] = [
            .idle, .recording(handsFree: false), .recording(handsFree: true),
            .transcribing, .cleaning, .inserting, .success, .error
        ]
        let styles: [PillStyle] = [.bareWaveform, .inkLine, .calmFlowRibbon, .bareWave,
                                   .dynamicIsland, .frostedGlass]

        for style in styles {
            for state in states {
                var presentation = PillPresentation.preview(state, errorMessage: "Preview error")
                presentation.style = style
                let image = try render(PillRendererView(
                    presentation: presentation,
                    levelSource: SimulatedAudioLevelSource(seed: 42, fixture: .conversation)))

                XCTAssertEqual(image.pixelsWide, Int(PillLayout.panelSize.width * 2))
                XCTAssertEqual(image.pixelsHigh, Int(PillLayout.panelSize.height * 2))
                XCTAssertTrue(containsVisiblePixel(image), "Blank render for \(style) / \(state)")
            }
        }
    }

    func testReducedMotionAndIncreasedContrastRenderDeterministically() throws {
        var presentation = PillPresentation.preview(.recording(handsFree: true))
        presentation.style = .frostedGlass
        presentation.reduceMotion = true
        presentation.increasedContrast = true

        let source = SimulatedAudioLevelSource(seed: 7, fixture: .quiet)
        let first = try render(PillRendererView(presentation: presentation, levelSource: source))
        let second = try render(PillRendererView(presentation: presentation, levelSource: source))

        XCTAssertEqual(first.representation(using: .png, properties: [:]),
                       second.representation(using: .png, properties: [:]))
    }

    func testChromelessInstantRecordingHasNoDecorativeModeBadge() throws {
        var instant = PillPresentation.preview(.recording(handsFree: false))
        instant.style = .bareWaveform
        instant.isInstant = true
        instant.reduceMotion = true
        var standard = instant
        standard.isInstant = false
        let source = SimulatedAudioLevelSource(seed: 11, fixture: .quiet)

        let instantImage = try render(PillRendererView(
            presentation: instant,
            levelSource: source,
            recordingStartedAt: nil))
        let standardImage = try render(PillRendererView(
            presentation: standard,
            levelSource: source,
            recordingStartedAt: nil))

        XCTAssertEqual(
            instantImage.representation(using: .png, properties: [:]),
            standardImage.representation(using: .png, properties: [:]))
    }

    func testMinimalRecordingHidesTimerByDefault() throws {
        var first = PillPresentation.preview(.recording(handsFree: false))
        first.reduceMotion = true
        first.elapsed = 1
        var second = first
        second.elapsed = 91
        let source = SimulatedAudioLevelSource(seed: 18, fixture: .conversation)

        let firstImage = try render(PillRendererView(
            presentation: first, levelSource: source, recordingStartedAt: nil))
        let secondImage = try render(PillRendererView(
            presentation: second, levelSource: source, recordingStartedAt: nil))

        XCTAssertEqual(firstImage.representation(using: .png, properties: [:]),
                       secondImage.representation(using: .png, properties: [:]))
    }

    func testVisibleCancelButtonIsIndependentOptInChrome() throws {
        var minimal = PillPresentation.preview(.recording(handsFree: false))
        minimal.reduceMotion = true
        var withCancel = minimal
        withCancel.showsCancelButton = true
        let source = SimulatedAudioLevelSource(seed: 19, fixture: .conversation)

        let minimalImage = try render(PillRendererView(
            presentation: minimal, levelSource: source, recordingStartedAt: nil))
        let cancelImage = try render(PillRendererView(
            presentation: withCancel, levelSource: source, recordingStartedAt: nil))

        XCTAssertNotEqual(minimalImage.representation(using: .png, properties: [:]),
                          cancelImage.representation(using: .png, properties: [:]))
    }

    func testProcessingAndCompletionUseSameNeutralRing() throws {
        var processing = PillPresentation.preview(.transcribing)
        processing.reduceMotion = true
        var completion = processing
        completion.state = .success
        let source = SimulatedAudioLevelSource(seed: 20, fixture: .quiet)

        let processingImage = try render(PillRendererView(
            presentation: processing, levelSource: source, recordingStartedAt: nil))
        let completionImage = try render(PillRendererView(
            presentation: completion, levelSource: source, recordingStartedAt: nil))

        XCTAssertEqual(processingImage.representation(using: .png, properties: [:]),
                       completionImage.representation(using: .png, properties: [:]))
    }

    func testReducedMotionOrganicWaveformStillRespondsToMicrophoneLevel() async throws {
        var presentation = PillPresentation.preview(.recording(handsFree: false))
        presentation.style = .inkLine
        presentation.audioLevel = 0
        presentation.reduceMotion = true
        let source = MutableLevelSource(level: 0)
        let hosting = makeHosting(PillRendererView(
            presentation: presentation,
            levelSource: source,
            recordingStartedAt: nil))
        let window = attachToWindow(hosting)
        defer { window.close() }

        try await Task.sleep(for: .milliseconds(180))
        let quiet = try snapshot(hosting)
        source.latestLevel = 1
        try await Task.sleep(for: .milliseconds(300))
        let loud = try snapshot(hosting)

        XCTAssertNotEqual(quiet.representation(using: .png, properties: [:]),
                          loud.representation(using: .png, properties: [:]))
    }

    private func render<V: View>(_ view: V) throws -> NSBitmapImageRep {
        try snapshot(makeHosting(view))
    }

    private func makeHosting<V: View>(_ view: V) -> NSHostingView<some View> {
        let size = NSSize(width: PillLayout.panelSize.width, height: PillLayout.panelSize.height)
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        return hosting
    }

    private func attachToWindow<V>(_ hosting: NSHostingView<V>) -> NSWindow where V: View {
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.contentView = hosting
        window.orderBack(nil)
        window.contentView?.layoutSubtreeIfNeeded()
        return window
    }

    private func snapshot<V>(_ hosting: NSHostingView<V>) throws -> NSBitmapImageRep where V: View {
        let size = hosting.frame.size
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * 2),
            pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0)
        else { throw RenderingError.couldNotAllocateBitmap }

        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
            throw RenderingError.couldNotCreateContext
        }
        NSGraphicsContext.current = context
        hosting.layer?.render(in: context.cgContext)
        hosting.draw(hosting.bounds)
        context.flushGraphics()
        return rep
    }

    private func containsVisiblePixel(_ image: NSBitmapImageRep) -> Bool {
        guard let data = image.bitmapData else { return false }
        let bytes = image.bytesPerRow * image.pixelsHigh
        return stride(from: 3, to: bytes, by: 4).contains { data[$0] > 0 }
    }

    private enum RenderingError: Error {
        case couldNotAllocateBitmap
        case couldNotCreateContext
    }
}
