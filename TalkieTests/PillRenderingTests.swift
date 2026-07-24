import AppKit
import SwiftUI
import XCTest
@testable import Talkie

@MainActor
final class PillRenderingTests: XCTestCase {
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

    private func render<V: View>(_ view: V) throws -> NSBitmapImageRep {
        let size = NSSize(width: PillLayout.panelSize.width, height: PillLayout.panelSize.height)
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()

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
