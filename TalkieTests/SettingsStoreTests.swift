import XCTest
@testable import Talkie

final class SettingsStoreTests: XCTestCase {
    func testDefaults() {
        let defaults = UserDefaults(suiteName: "talkie-tests-\(UUID().uuidString)")!
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.transcriptionModel, "gpt-transcribe")
        XCTAssertEqual(store.cleanupModel, "google/gemini-2.5-flash-lite") // measured 3x faster than flash
        XCTAssertEqual(store.cleanupProvider, "openrouter")
        XCTAssertEqual(store.transcriptionProvider, "openai")
        XCTAssertEqual(store.openrouterTranscriptionModel, "mistralai/voxtral-mini-transcribe")
    }

    func testNewTranscriptionDefaults() {
        let defaults = UserDefaults(suiteName: "talkie-tests-\(UUID().uuidString)")!
        let store = SettingsStore(defaults: defaults)

        XCTAssertEqual(store.transcriptionModel, "gpt-transcribe")
        XCTAssertEqual(store.realtimeTranscriptionModel, "gpt-live-transcribe")
        XCTAssertEqual(store.realtimeTranscriptionDelay, .medium)
        XCTAssertEqual(store.transcriptionContextPrompt, "")
        XCTAssertEqual(store.expectedInputLanguages, [])
        XCTAssertTrue(store.streamBatchTranscription)
        XCTAssertFalse(store.speakerFilteringEnabled)
    }

    func testSpeakerFilteringPersistsAndSelectsSupportedPipeline() {
        let suite = "talkie-tests-\(UUID().uuidString)"
        let store = SettingsStore(defaults: UserDefaults(suiteName: suite)!)
        store.engineMode = "instant"
        store.transcriptionProvider = "openrouter"
        store.instantLiveType = true

        store.speakerFilteringEnabled = true

        XCTAssertEqual(store.engineMode, "cloud")
        XCTAssertEqual(store.transcriptionProvider, "openai")
        XCTAssertFalse(store.instantLiveType)
        XCTAssertTrue(SettingsStore(
            defaults: UserDefaults(suiteName: suite)!).speakerFilteringEnabled)
    }

    func testExistingModelSelectionIsPreserved() {
        let defaults = UserDefaults(suiteName: "talkie-tests-\(UUID().uuidString)")!
        defaults.set("gpt-4o-mini-transcribe", forKey: "transcriptionModel")

        XCTAssertEqual(
            SettingsStore(defaults: defaults).transcriptionModel,
            "gpt-4o-mini-transcribe")
    }

    func testRealtimeWhisperSelectionIsPreservedAsAnAlternative() {
        let defaults = UserDefaults(suiteName: "talkie-tests-\(UUID().uuidString)")!
        defaults.set("gpt-realtime-whisper", forKey: "realtimeTranscriptionModel")

        let store = SettingsStore(defaults: defaults)

        XCTAssertEqual(store.realtimeTranscriptionModel, "gpt-realtime-whisper")
    }

    func testExpectedLanguagesMigrateOnceFromPinnedLanguage() {
        let defaults = UserDefaults(suiteName: "talkie-tests-\(UUID().uuidString)")!
        defaults.set("de", forKey: "pinnedLanguage")

        let store = SettingsStore(defaults: defaults)

        XCTAssertEqual(store.expectedInputLanguages, ["de"])
        XCTAssertEqual(defaults.stringArray(forKey: "expectedInputLanguages"), ["de"])

        store.expectedInputLanguages = []
        XCTAssertEqual(SettingsStore(defaults: defaults).expectedInputLanguages, [])
    }

    func testNewDefaults() {
        let defaults = UserDefaults(suiteName: "talkie-tests-\(UUID().uuidString)")!
        let store = SettingsStore(defaults: defaults)
        XCTAssertTrue(store.showFlowBar)
        XCTAssertFalse(store.launchAtLogin)
        XCTAssertEqual(store.engineMode, "cloud")
        XCTAssertFalse(store.showDockIcon)
        XCTAssertFalse(store.keepRecordings)
        XCTAssertFalse(store.instantSkipCleanup)
        XCTAssertFalse(store.enablePressEnterAction)
        XCTAssertFalse(store.contextAwarenessEnabled)
        XCTAssertTrue(store.contextExcludedBundleIDs.isEmpty)
        XCTAssertEqual(store.pillStyle, .bareWaveform)
        XCTAssertEqual(store.pillPosition, "bottomCenter")
        XCTAssertFalse(store.showPillTimer)
        XCTAssertFalse(store.showPillCancelButton)
    }

    func testPillChromePreferencesRoundTripIndependently() {
        let defaults = UserDefaults(suiteName: "talkie-tests-\(UUID().uuidString)")!
        let store = SettingsStore(defaults: defaults)
        store.showPillTimer = true
        XCTAssertTrue(SettingsStore(defaults: defaults).showPillTimer)
        XCTAssertFalse(SettingsStore(defaults: defaults).showPillCancelButton)

        store.showPillCancelButton = true
        XCTAssertTrue(SettingsStore(defaults: defaults).showPillCancelButton)
    }

    func testPressEnterActionRoundTrips() {
        let suite = "talkie-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = SettingsStore(defaults: defaults)
        store.enablePressEnterAction = true
        XCTAssertTrue(SettingsStore(defaults: defaults).enablePressEnterAction)
    }

    func testInstantSkipCleanupRoundTrips() {
        let suite = "talkie-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = SettingsStore(defaults: defaults)
        store.instantSkipCleanup = true
        XCTAssertTrue(SettingsStore(defaults: defaults).instantSkipCleanup)
    }

    func testEnablingLiveTypeForcesSkipCleanup() {
        let store = SettingsStore(defaults: UserDefaults(suiteName: "talkie-tests-\(UUID().uuidString)")!)
        store.instantSkipCleanup = false
        store.instantLiveType = true
        XCTAssertTrue(store.instantSkipCleanup) // can't re-polish already-typed text
        XCTAssertTrue(store.instantLiveType)
    }

    func testRetiredPillStylesMigrateToBareWaveform() {
        for legacy in ["classic", "dot", "compact", "totally-unknown"] {
            let defaults = UserDefaults(suiteName: "talkie-tests-\(UUID().uuidString)")!
            defaults.set(legacy, forKey: "pillStyle")
            let store = SettingsStore(defaults: defaults)
            XCTAssertEqual(store.pillStyle, .bareWaveform, legacy)
            // Migration is persisted normalized so `defaults read` no longer shows the legacy value.
            XCTAssertEqual(defaults.string(forKey: "pillStyle"), "bareWaveform", legacy)
        }
    }

    func testHiddenPillStyleSurvivesMigration() {
        let defaults = UserDefaults(suiteName: "talkie-tests-\(UUID().uuidString)")!
        defaults.set("hidden", forKey: "pillStyle")
        XCTAssertEqual(SettingsStore(defaults: defaults).pillStyle, .hidden)
    }

    func testPillStyleRoundTrips() {
        let suite = "talkie-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = SettingsStore(defaults: defaults)
        store.pillStyle = .frostedGlass
        XCTAssertEqual(SettingsStore(defaults: defaults).pillStyle, .frostedGlass)
    }

    func testOrganicPillStylesSurviveMigrationAndRoundTrip() {
        let cases: [PillStyle] = [.inkLine, .calmFlowRibbon, .bareWave]
        for style in cases {
            let defaults = UserDefaults(suiteName: "talkie-tests-\(UUID().uuidString)")!
            defaults.set(style.rawValue, forKey: "pillStyle")
            XCTAssertEqual(SettingsStore(defaults: defaults).pillStyle, style)
        }
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
