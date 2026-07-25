import XCTest
@testable import Talkie

@MainActor
final class SetupStateStoreTests: XCTestCase {
    private var suites: [String] = []

    override func tearDown() {
        for suite in suites {
            UserDefaults.standard.removePersistentDomain(forName: suite)
        }
        suites.removeAll()
        super.tearDown()
    }

    func testFreshInstallationStartsIncomplete() {
        let defaults = makeDefaults()

        let store = SetupStateStore(defaults: defaults)

        XCTAssertFalse(store.setupCompleted)
        XCTAssertEqual(defaults.integer(forKey: SetupStateStore.stateVersionKey),
                       SetupStateStore.currentStateVersion)
    }

    func testLegacyConfigurationMigratesAsCompleted() {
        let defaults = makeDefaults()
        defaults.set("instant", forKey: "engineMode")

        let store = SetupStateStore(defaults: defaults)

        XCTAssertTrue(store.setupCompleted)
        XCTAssertTrue(defaults.bool(forKey: SetupStateStore.completedKey))
    }

    func testUnrelatedDefaultsDoNotCountAsLegacyConfiguration() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "unrelatedPreference")

        let store = SetupStateStore(defaults: defaults)

        XCTAssertFalse(store.setupCompleted)
    }

    func testExplicitIncompleteStateWinsOverLegacyEvidence() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: SetupStateStore.completedKey)
        defaults.set(SetupStateStore.currentStateVersion,
                     forKey: SetupStateStore.stateVersionKey)
        defaults.set("instant", forKey: "engineMode")

        let store = SetupStateStore(defaults: defaults)

        XCTAssertFalse(store.setupCompleted)
    }

    func testCompletionPersistsAcrossRelaunch() {
        let defaults = makeDefaults()
        let firstLaunch = SetupStateStore(defaults: defaults)

        firstLaunch.markCompleted()
        let relaunched = SetupStateStore(defaults: defaults)

        XCTAssertTrue(relaunched.setupCompleted)
        XCTAssertFalse(SetupLaunchPolicy.shouldShowOnboarding(
            setupCompleted: relaunched.setupCompleted,
            microphoneGranted: false,
            accessibilityGranted: false))
    }

    func testIncompleteSetupShowsRegardlessOfPermissionState() {
        XCTAssertTrue(SetupLaunchPolicy.shouldShowOnboarding(
            setupCompleted: false,
            microphoneGranted: true,
            accessibilityGranted: true))
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "TalkieTests.SetupState.\(UUID().uuidString)"
        suites.append(suite)
        UserDefaults.standard.removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite)!
    }
}
