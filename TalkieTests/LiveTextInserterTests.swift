import XCTest
@testable import Talkie

@MainActor
final class LiveTextInserterTests: XCTestCase {
    final class MockOwnedRange: LiveTextOwnedRangeReplacing {
        var canBegin = true
        var value = ""
        var replaceAllowed = true
        var replacements: [(expected: String, replacement: String)] = []
        func begin(targetBundleID: String?) -> Bool { canBegin }
        func replace(expected: String, with replacement: String) -> Bool {
            replacements.append((expected, replacement))
            guard replaceAllowed, value == expected else { return false }
            value = replacement
            return true
        }
        func reset() { value = "" }
    }

    func testSuffixDiffEmitsOnlyNewCharacters() {
        XCTAssertEqual(LiveTextInserter.suffix(committed: "the quick", accumulated: "the quick brown"), " brown")
    }

    func testSuffixDiffEmptyWhenNoGrowth() {
        XCTAssertEqual(LiveTextInserter.suffix(committed: "abc", accumulated: "abc"), "")
    }

    func testNonPrefixRevisionHasNoAppendSuffix() {
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

    func testOwnedRangeRepairsNonPrefixRevision() throws {
        let range = MockOwnedRange()
        let inserter = LiveTextInserter(secureInputCheck: { false }, axTrustedCheck: { true },
                                        postUnicode: { _ in XCTFail("AX path must not type events"); return false },
                                        ownedRange: range)
        inserter.reset(targetBundleID: "com.example.editor")
        XCTAssertTrue(try inserter.type(upTo: "I went"))
        XCTAssertTrue(try inserter.type(upTo: "I want"))
        XCTAssertEqual(range.value, "I want")
        XCTAssertEqual(inserter.revisionCount, 1)
        XCTAssertEqual(try inserter.finalize(authoritative: "I want"),
                       .repaired(route: .accessibilityRange, verification: .verified,
                                 revisionCount: 1))
    }

    func testOwnedRangeRevisionIsUnicodeAndEmojiSafe() throws {
        let range = MockOwnedRange()
        let inserter = LiveTextInserter(secureInputCheck: { false }, axTrustedCheck: { true },
                                        ownedRange: range)
        inserter.reset(targetBundleID: "com.example.editor")
        _ = try inserter.type(upTo: "Café 👩‍👩‍👧‍👦")
        _ = try inserter.type(upTo: "Café 👩🏽‍💻")
        XCTAssertEqual(range.value, "Café 👩🏽‍💻")
        XCTAssertEqual(inserter.revisionCount, 1)
    }

    func testOwnershipLossFailsClosedWithoutUnicodeFallback() throws {
        let range = MockOwnedRange()
        var typed: [String] = []
        let inserter = LiveTextInserter(secureInputCheck: { false }, axTrustedCheck: { true },
                                        postUnicode: { typed.append($0); return true }, ownedRange: range)
        inserter.reset(targetBundleID: "com.example.editor")
        _ = try inserter.type(upTo: "owned")
        range.value = "user changed it" // field contents changed or another field was focused
        XCTAssertFalse(try inserter.type(upTo: "owned text"))
        XCTAssertEqual(try inserter.finalize(authoritative: "owned text"),
                       .clipboardFallback(reason: "live_text_ownership_lost", revisionCount: 0))
        XCTAssertTrue(typed.isEmpty)
    }

    func testAppendOnlyRevisionWaitsForClipboardFallbackAndNeverDeletes() throws {
        let range = MockOwnedRange()
        range.canBegin = false
        var typed: [String] = []
        let inserter = LiveTextInserter(secureInputCheck: { false }, axTrustedCheck: { true },
                                        postUnicode: { typed.append($0); return true }, ownedRange: range)
        inserter.reset(targetBundleID: "com.example.terminal")
        _ = try inserter.type(upTo: "I went")
        _ = try inserter.type(upTo: "I want")
        XCTAssertEqual(typed, ["I went"])
        XCTAssertEqual(try inserter.finalize(authoritative: "I want there"),
                       .clipboardFallback(reason: "live_text_revision_unrepairable", revisionCount: 2))
    }

    func testFinalTranscriptRepairsLastPartialInOwnedRange() throws {
        let range = MockOwnedRange()
        let inserter = LiveTextInserter(secureInputCheck: { false }, axTrustedCheck: { true },
                                        ownedRange: range)
        inserter.reset(targetBundleID: "com.example.editor")
        _ = try inserter.type(upTo: "final partal")
        XCTAssertEqual(try inserter.finalize(authoritative: "final partial"),
                       .repaired(route: .accessibilityRange, verification: .verified,
                                 revisionCount: 1))
        XCTAssertEqual(range.value, "final partial")
    }

    func testEraseRequiresOwnedRangeAndVerifiesContents() throws {
        let range = MockOwnedRange()
        let inserter = LiveTextInserter(secureInputCheck: { false }, axTrustedCheck: { true },
                                        ownedRange: range)
        inserter.reset(targetBundleID: "com.example.editor")
        _ = try inserter.type(upTo: "raw")
        XCTAssertTrue(try inserter.eraseTyped())
        XCTAssertEqual(range.value, "")

        inserter.reset(targetBundleID: "com.example.editor")
        _ = try inserter.type(upTo: "raw")
        range.value = "user modified raw"
        XCTAssertFalse(try inserter.eraseTyped())
        XCTAssertEqual(range.value, "user modified raw")
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
