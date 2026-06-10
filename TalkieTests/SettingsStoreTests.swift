import XCTest
@testable import Talkie

final class SettingsStoreTests: XCTestCase {
    func testDefaults() {
        let defaults = UserDefaults(suiteName: "talkie-tests-\(UUID().uuidString)")!
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.transcriptionModel, "gpt-4o-mini-transcribe")
        XCTAssertEqual(store.cleanupModel, "google/gemini-2.5-flash")
    }

    func testPersistence() {
        let suite = "talkie-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = SettingsStore(defaults: defaults)
        store.transcriptionModel = "whisper-1"
        XCTAssertEqual(SettingsStore(defaults: defaults).transcriptionModel, "whisper-1")
    }
}
