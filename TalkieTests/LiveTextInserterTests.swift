import XCTest
@testable import Talkie

@MainActor
final class LiveTextInserterTests: XCTestCase {
    func testSuffixDiffEmitsOnlyNewCharacters() {
        XCTAssertEqual(LiveTextInserter.suffix(committed: "the quick", accumulated: "the quick brown"), " brown")
    }

    func testSuffixDiffEmptyWhenNoGrowth() {
        XCTAssertEqual(LiveTextInserter.suffix(committed: "abc", accumulated: "abc"), "")
    }

    func testNonPrefixRevisionIsSkipped() {
        XCTAssertNil(LiveTextInserter.suffix(committed: "the quik", accumulated: "the quick"))
    }

    func testGraphemeBoundaryNotSplit() {
        // Growing by a multi-scalar emoji yields the whole grapheme, not half of it.
        let add = LiveTextInserter.suffix(committed: "ok ", accumulated: "ok 👩‍👩‍👧‍👦")
        XCTAssertEqual(add, "👩‍👩‍👧‍👦")
        XCTAssertEqual(add?.count, 1)
    }

    func testTypesAppendedSuffixOnlyAcrossCalls() throws {
        var typed: [String] = []
        let inserter = LiveTextInserter(secureInputCheck: { false }, axTrustedCheck: { true },
                                        postUnicode: { typed.append($0); return true })
        XCTAssertTrue(try inserter.type(upTo: "hello"))
        XCTAssertTrue(try inserter.type(upTo: "hello world"))
        XCTAssertEqual(typed, ["hello", " world"]) // only the new suffix each time
    }

    func testSecureInputBailsWithoutTyping() {
        var typed: [String] = []
        let inserter = LiveTextInserter(secureInputCheck: { true }, axTrustedCheck: { true },
                                        postUnicode: { typed.append($0); return true })
        XCTAssertThrowsError(try inserter.type(upTo: "secret")) { error in
            XCTAssertEqual(error as? InsertionError, .secureInputActive)
        }
        XCTAssertTrue(typed.isEmpty)
    }

    func testNoAXTrustBailsSafely() throws {
        var typed: [String] = []
        let inserter = LiveTextInserter(secureInputCheck: { false }, axTrustedCheck: { false },
                                        postUnicode: { typed.append($0); return true })
        XCTAssertFalse(try inserter.type(upTo: "hello")) // not viable → caller falls back
        XCTAssertTrue(typed.isEmpty)                     // nothing typed, no throw
    }
}
