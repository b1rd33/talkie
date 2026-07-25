import XCTest
@testable import Talkie

final class ContextPrivacyTests: XCTestCase {
    func testContextPolicyIsOffByDefaultAndHonorsExclusions() {
        XCTAssertFalse(ContextPolicy.mayRead(enabled: false, bundleID: "com.apple.TextEdit", exclusions: []))
        XCTAssertFalse(ContextPolicy.mayRead(enabled: true, bundleID: "com.secret.app", exclusions: ["com.secret.app"]))
        XCTAssertTrue(ContextPolicy.mayRead(enabled: true, bundleID: "com.apple.TextEdit", exclusions: []))
    }

    func testBoundedContextKeepsOnlyNearbyText() {
        let value = String(repeating: "a", count: 700) + "CURSOR" + String(repeating: "b", count: 700)
        let context = FocusedContext.bounded(value: value, cursorUTF16Offset: 706, selection: nil,
                                             surroundingLimit: 500)
        XCTAssertEqual(context?.precedingText.count, 500)
        XCTAssertEqual(context?.followingText.count, 500)
        XCTAssertTrue(context?.precedingText.hasSuffix("CURSOR") == true)
    }

    func testSmartInsertionUsesCursorBoundary() {
        XCTAssertEqual(SmartInsertionProcessor.format("hello world", precedingText: "Done. "), "Hello world")
        XCTAssertEqual(SmartInsertionProcessor.format("next", precedingText: "hello"), " next")
        XCTAssertEqual(SmartInsertionProcessor.format("next", precedingText: "hello "), "next")
    }
}
