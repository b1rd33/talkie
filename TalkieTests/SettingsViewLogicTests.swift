import XCTest
@testable import Talkie

@MainActor
final class SettingsViewLogicTests: XCTestCase {
    private func store(engine: String, skip: Bool) -> SettingsStore {
        let s = SettingsStore(defaults: UserDefaults(suiteName: "talkie-tests-\(UUID().uuidString)")!)
        s.engineMode = engine
        s.instantSkipCleanup = skip
        return s
    }

    func testCleanupInactiveOnlyWhenInstantAndSkip() {
        XCTAssertTrue(cleanupInactive(store(engine: "instant", skip: true)))
        XCTAssertFalse(cleanupInactive(store(engine: "instant", skip: false)))
        XCTAssertFalse(cleanupInactive(store(engine: "cloud", skip: true)))
        XCTAssertFalse(cleanupInactive(store(engine: "local", skip: true)))
    }

    func testCleanupInactiveWhenInstantLiveType() {
        let s = store(engine: "instant", skip: false)
        s.instantLiveType = true // forces skip on, and independently inactivates cleanup
        XCTAssertTrue(cleanupInactive(s))
        let cloud = store(engine: "cloud", skip: false)
        cloud.instantLiveType = true
        XCTAssertFalse(cleanupInactive(cloud)) // only in instant mode
    }

    func testPrivacyPolicyLinkIsHTTPS() {
        XCTAssertEqual(ProjectLinks.privacyPolicy.scheme, "https")
        XCTAssertEqual(ProjectLinks.privacyPolicy.host, "github.com")
    }

    func testPrivacyModesHaveFourDistinctNonemptyLabels() {
        let labels = PrivacyMode.allCases.map(\.label)

        XCTAssertEqual(labels.count, 4)
        XCTAssertEqual(Set(labels).count, labels.count)
        XCTAssertTrue(labels.allSatisfy {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })
    }

    func testPrivacyLinkCopyIsCentralizedAndNonempty() {
        XCTAssertFalse(PrivacyCopy.policyLinkLabel
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertFalse(PrivacyCopy.audioRetentionSummary
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
