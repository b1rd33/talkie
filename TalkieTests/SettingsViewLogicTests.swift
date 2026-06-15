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
}
