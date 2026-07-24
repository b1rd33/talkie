import XCTest
@testable import Talkie

@MainActor
final class SettingsViewLogicTests: XCTestCase {
    private func repositoryFile(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath),
                          encoding: .utf8)
    }

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

    func testPrivacyPolicyUsesOpenAIAPITermsAndDataPractices() throws {
        let policy = try repositoryFile("PRIVACY.md")

        XCTAssertTrue(policy.contains("https://openai.com/policies/services-agreement/"))
        XCTAssertTrue(policy.contains("https://openai.com/policies/service-terms/"))
        XCTAssertTrue(policy.contains("https://developers.openai.com/api/docs/guides/your-data"))
        XCTAssertFalse(policy.contains("https://openai.com/policies/privacy-policy/"))
        XCTAssertFalse(policy.contains("https://openai.com/policies/terms-of-use/"))
    }

    func testOnboardingCaptureCopyIncludesHandsFree() throws {
        let source = try repositoryFile("Talkie/UI/Onboarding/OnboardingView.swift")

        XCTAssertTrue(source.contains("hands-free recording is active"))
        XCTAssertFalse(source.contains("records only while you hold the dictation key"))
    }
}
