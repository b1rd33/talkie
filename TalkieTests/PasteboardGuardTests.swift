import XCTest
@testable import Talkie

@MainActor
final class PasteboardGuardTests: XCTestCase {
    private let pasteboard = NSPasteboard.general

    func testWritePutsTextOnPasteboard() {
        let guard_ = PasteboardGuard()
        guard_.snapshotAndWrite("from talkie")
        XCTAssertEqual(pasteboard.string(forType: .string), "from talkie")
    }

    func testRestoreBringsBackPriorContents() {
        pasteboard.clearContents()
        pasteboard.setString("user's precious copy", forType: .string)
        let guard_ = PasteboardGuard()
        guard_.snapshotAndWrite("from talkie")
        guard_.restoreIfUnchanged()
        XCTAssertEqual(pasteboard.string(forType: .string), "user's precious copy")
    }

    func testRestoreSkippedWhenSomeoneElseWroteAfterUs() {
        pasteboard.clearContents()
        pasteboard.setString("original", forType: .string)
        let guard_ = PasteboardGuard()
        guard_.snapshotAndWrite("from talkie")
        pasteboard.clearContents()
        pasteboard.setString("newer copy by user", forType: .string) // bumps changeCount
        guard_.restoreIfUnchanged()
        XCTAssertEqual(pasteboard.string(forType: .string), "newer copy by user")
    }

    func testRestoreWithEmptyPriorPasteboardClears() {
        pasteboard.clearContents() // changeCount bumps, no items
        let guard_ = PasteboardGuard()
        guard_.snapshotAndWrite("from talkie")
        guard_.restoreIfUnchanged()
        XCTAssertNil(pasteboard.string(forType: .string))
    }
}
