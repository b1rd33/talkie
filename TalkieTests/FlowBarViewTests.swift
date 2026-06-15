import XCTest
@testable import Talkie

final class FlowBarViewTests: XCTestCase {
    func testTailReturnsLastNCharacters() {
        XCTAssertEqual(FlowBarView.tail("the quick brown fox", max: 5), "n fox")
    }

    func testTailEmptyStaysEmpty() {
        XCTAssertEqual(FlowBarView.tail("", max: 5), "")
    }

    func testTailShorterThanMaxReturnsWhole() {
        XCTAssertEqual(FlowBarView.tail("hi", max: 5), "hi")
    }

    func testTailNeverExceedsMaxCharacters() {
        let out = FlowBarView.tail("abcdefghij", max: 4)
        XCTAssertEqual(out.count, 4)
        XCTAssertEqual(out, "ghij")
    }

    func testTailCountsGraphemesNotScalars() {
        // A family emoji is one Character but many scalars — must not be split.
        let s = "ok 👩‍👩‍👧‍👦"
        let out = FlowBarView.tail(s, max: 1)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out, "👩‍👩‍👧‍👦")
    }
}
