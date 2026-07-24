import AppKit
import XCTest

final class IconStudyAssetTests: XCTestCase {
    private var directory: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("design-studies/icons")
    }

    func testFourDistinctReviewIconsExistAtMasterSize() throws {
        let names = ["notch-voice", "ink-wave", "glass-slit", "orbit"]
        var payloads: [Data] = []
        for name in names {
            let data = try Data(contentsOf: directory.appendingPathComponent("\(name).png"))
            let image = try XCTUnwrap(NSBitmapImageRep(data: data))
            XCTAssertEqual(image.pixelsWide, 1024, name)
            XCTAssertEqual(image.pixelsHigh, 1024, name)
            XCTAssertGreaterThan(image.colorAt(x: 512, y: 512)?.alphaComponent ?? 0, 0.9, name)
            payloads.append(data)
        }
        for left in payloads.indices {
            for right in payloads.indices where left < right {
                XCTAssertNotEqual(payloads[left], payloads[right])
            }
        }
    }
}
