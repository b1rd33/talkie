import AppKit
import XCTest

final class AppIconAssetTests: XCTestCase {
    private var iconDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Talkie/Assets.xcassets/AppIcon.appiconset")
    }

    func testEveryDeclaredMacIconExistsAtExactPixelDimensions() throws {
        let data = try Data(contentsOf: iconDirectory.appendingPathComponent("Contents.json"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let images = try XCTUnwrap(json["images"] as? [[String: String]])

        XCTAssertEqual(images.count, 10)
        for slot in images {
            let filename = try XCTUnwrap(slot["filename"])
            let logical = try XCTUnwrap(slot["size"]?.split(separator: "x").first)
            let scale = slot["scale"] == "2x" ? 2 : 1
            let expected = try XCTUnwrap(Int(logical)).multipliedReportingOverflow(by: scale).partialValue
            let rep = try load(filename)
            XCTAssertEqual(rep.pixelsWide, expected, filename)
            XCTAssertEqual(rep.pixelsHigh, expected, filename)
        }
    }

    func testMasterUsesNativeDepthPaletteAndWaveformHierarchy() throws {
        let image = try load("icon_512x512@2x.png")
        let corner = rgba(image, x: 4, y: 4)
        let navy = rgba(image, x: 512, y: 760)
        let cyanBar = rgba(image, x: 372, y: 512)
        let voicePeak = rgba(image, x: 512, y: 512)

        XCTAssertLessThan(corner.a, 0.08, "macOS icon canvas should keep transparent corners")
        XCTAssertGreaterThan(navy.a, 0.98)
        XCTAssertGreaterThan(navy.b, navy.r * 1.35, "tile should read as deep navy")
        XCTAssertGreaterThan(cyanBar.g, cyanBar.r * 1.3, "outer voice bar should read cyan")
        XCTAssertGreaterThan(cyanBar.b, cyanBar.r * 1.3)
        XCTAssertGreaterThan(luminance(voicePeak), 0.78, "central voice peak should remain bright")
    }

    func testSmallestIconKeepsOpaqueCenterAndTransparentCorners() throws {
        let image = try load("icon_16x16.png")
        XCTAssertLessThan(rgba(image, x: 0, y: 0).a, 0.15)
        XCTAssertGreaterThan(rgba(image, x: 8, y: 8).a, 0.95)
    }

    private func load(_ filename: String) throws -> NSBitmapImageRep {
        let data = try Data(contentsOf: iconDirectory.appendingPathComponent(filename))
        return try XCTUnwrap(NSBitmapImageRep(data: data), filename)
    }

    private func rgba(_ image: NSBitmapImageRep, x: Int, y: Int) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) ?? .clear
        return (color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent)
    }

    private func luminance(_ sample: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)) -> CGFloat {
        sample.r * 0.2126 + sample.g * 0.7152 + sample.b * 0.0722
    }
}
