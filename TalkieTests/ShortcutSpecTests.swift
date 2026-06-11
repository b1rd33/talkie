import XCTest
@testable import Talkie

final class ShortcutSpecTests: XCTestCase {
    func testRoundTrip() throws {
        let spec = try XCTUnwrap(ShortcutSpec(storage: "cmd+shift+d"))
        XCTAssertEqual(spec.storage, "cmd+shift+d")
        XCTAssertEqual(spec.display, "⌘⇧D")
        XCTAssertEqual(spec.key, .d)
        XCTAssertTrue(spec.modifiers.contains(.command))
        XCTAssertTrue(spec.modifiers.contains(.shift))
    }

    func testBareKeyWithoutModifiersRejected() {
        XCTAssertNil(ShortcutSpec(storage: "d")) // would swallow normal typing
    }

    func testUnknownKeyRejected() {
        XCTAssertNil(ShortcutSpec(storage: "cmd+notakey"))
    }

    func testFunctionKeysAllowedWithoutModifiers() throws {
        let spec = try XCTUnwrap(ShortcutSpec(storage: "f13"))
        XCTAssertEqual(spec.display, "F13")
        XCTAssertTrue(spec.modifiers.isEmpty)
    }
}
