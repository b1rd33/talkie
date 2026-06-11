import XCTest
@testable import Talkie

final class SettingsStoreTests: XCTestCase {
    func testDefaults() {
        let defaults = UserDefaults(suiteName: "talkie-tests-\(UUID().uuidString)")!
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.transcriptionModel, "gpt-4o-mini-transcribe")
        XCTAssertEqual(store.cleanupModel, "google/gemini-2.5-flash-lite") // measured 3x faster than flash
        XCTAssertEqual(store.cleanupProvider, "openrouter")
        XCTAssertEqual(store.transcriptionProvider, "openai")
        XCTAssertEqual(store.openrouterTranscriptionModel, "mistralai/voxtral-mini-transcribe")
    }

    func testNewDefaults() {
        let defaults = UserDefaults(suiteName: "talkie-tests-\(UUID().uuidString)")!
        let store = SettingsStore(defaults: defaults)
        XCTAssertTrue(store.showFlowBar)
        XCTAssertFalse(store.launchAtLogin)
        XCTAssertEqual(store.engineMode, "cloud")
        XCTAssertFalse(store.showDockIcon)
        XCTAssertFalse(store.keepRecordings)
        XCTAssertEqual(store.pillStyle, "classic")
        XCTAssertEqual(store.pillPosition, "bottomCenter")
    }

    func testStyleDefaults() {
        let defaults = UserDefaults(suiteName: "talkie-tests-\(UUID().uuidString)")!
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.cleanupLevel, "high")
        XCTAssertNil(store.pinnedLanguage)
        XCTAssertEqual(store.customCleanupPrompt, "")
    }

    func testPinnedLanguageRoundTripsThroughNil() {
        let suite = "talkie-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = SettingsStore(defaults: defaults)
        store.pinnedLanguage = "de"
        XCTAssertEqual(SettingsStore(defaults: defaults).pinnedLanguage, "de")
        store.pinnedLanguage = nil
        XCTAssertNil(SettingsStore(defaults: defaults).pinnedLanguage)
    }

    func testPersistence() {
        let suite = "talkie-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = SettingsStore(defaults: defaults)
        store.transcriptionModel = "whisper-1"
        XCTAssertEqual(SettingsStore(defaults: defaults).transcriptionModel, "whisper-1")
    }
}
