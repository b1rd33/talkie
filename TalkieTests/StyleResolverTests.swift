import XCTest
@testable import Talkie

final class StyleResolverTests: XCTestCase {
    func testBuiltInTable() {
        let resolver = StyleResolver()
        XCTAssertEqual(resolver.resolve(bundleID: "com.tinyspeck.slackmacgap"), .casual)   // Slack
        XCTAssertEqual(resolver.resolve(bundleID: "com.apple.MobileSMS"), .casual)         // Messages
        XCTAssertEqual(resolver.resolve(bundleID: "com.apple.mail"), .polished)            // Mail
        XCTAssertEqual(resolver.resolve(bundleID: "com.apple.dt.Xcode"), .technical)       // Xcode
        XCTAssertEqual(resolver.resolve(bundleID: "com.googlecode.iterm2"), .technical)    // iTerm2
    }

    func testUnknownAppIsNeutral() {
        XCTAssertEqual(StyleResolver().resolve(bundleID: "com.example.unknown"), .neutral)
    }

    func testNilBundleIDIsNeutral() {
        XCTAssertEqual(StyleResolver().resolve(bundleID: nil), .neutral)
    }

    func testUserOverrideBeatsBuiltIn() {
        let resolver = StyleResolver(overrides: { ["com.apple.dt.Xcode": "casual"] })
        XCTAssertEqual(resolver.resolve(bundleID: "com.apple.dt.Xcode"), .casual)
    }

    func testGarbageOverrideFallsBackToBuiltIn() {
        let resolver = StyleResolver(overrides: { ["com.apple.dt.Xcode": "extreme"] })
        XCTAssertEqual(resolver.resolve(bundleID: "com.apple.dt.Xcode"), .technical)
    }

    func testCleanupLevelRawValues() {
        XCTAssertEqual(CleanupLevel(rawValue: "high"), .high)
        XCTAssertEqual(CleanupLevel(rawValue: "none"), CleanupLevel.none)
        XCTAssertNil(CleanupLevel(rawValue: "extreme"))
    }
}
