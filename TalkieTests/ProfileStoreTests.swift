import XCTest
@testable import Talkie

final class ProfileStoreTests: XCTestCase {

    private func suite() -> UserDefaults {
        UserDefaults(suiteName: "talkie-profilestore-tests-\(UUID().uuidString)")!
    }
    private func settings(_ d: UserDefaults) -> SettingsStore { SettingsStore(defaults: d) }

    // MARK: persistence

    func testRoundTripPersistence() {
        let d = suite()
        let store = ProfileStore(defaults: d)
        var custom = DictationProfile.bestAccuracy
        custom.id = UUID(); custom.name = "Mine"; custom.builtIn = false
        store.add(custom)
        store.select(custom.id)

        let reloaded = ProfileStore(defaults: d)
        XCTAssertEqual(reloaded.customProfiles.map(\.name), ["Mine"])
        XCTAssertEqual(reloaded.selectedProfileID, custom.id)
        XCTAssertEqual(reloaded.selectedProfile?.name, "Mine")
    }

    func testAllProfilesIncludesBuiltInsThenCustom() {
        let store = ProfileStore(defaults: suite())
        var custom = DictationProfile.instant; custom.id = UUID(); custom.name = "X"; custom.builtIn = false
        store.add(custom)
        XCTAssertEqual(store.allProfiles.count, DictationProfile.builtIns.count + 1)
        XCTAssertEqual(store.allProfiles.last?.name, "X")
    }

    // MARK: migration

    func testMigrationOfShippingDefaultBecomesMySettingsBoth() {
        let d = suite()
        let s = settings(d) // fresh = shipping default: cloud / openai transcribe / openrouter cleanup / high
        let store = ProfileStore(defaults: d)
        store.migrateIfNeeded(from: s)
        let selected = store.selectedProfile
        XCTAssertNotNil(selected)
        XCTAssertEqual(selected?.name, "My Settings")
        XCTAssertEqual(selected?.builtIn, false)
        XCTAssertEqual(selected?.requiredKey, .both)
        XCTAssertEqual(store.customProfiles.count, 1)
    }

    func testMigrationPreservesTunedConfigVerbatim() {
        // A tuned config that happens to share a built-in's shape must still be preserved
        // EXACTLY (not snapped to the built-in's models/level), so migration never
        // silently downgrades the user's settings.
        let d = suite()
        let s = settings(d)
        s.engineMode = "instant"
        s.instantSkipCleanup = false
        s.cleanupProvider = "openai"
        s.cleanupModel = "gpt-5.4-mini" // Instant built-in pins gpt-5.4-nano
        s.cleanupLevel = "high"         // Instant built-in pins medium
        let store = ProfileStore(defaults: d)
        store.migrateIfNeeded(from: s)
        let selected = store.selectedProfile
        XCTAssertEqual(selected?.name, "My Settings")
        XCTAssertEqual(selected?.builtIn, false)
        XCTAssertEqual(selected?.cleanupModel, "gpt-5.4-mini") // exact value preserved
        XCTAssertEqual(selected?.cleanupLevel, "high")
        XCTAssertEqual(store.customProfiles.count, 1)
    }

    func testMigrationReMigratesWhenSelectedIdIsStale() {
        // A persisted selectedProfileID that no longer matches any profile (e.g. custom
        // JSON failed to decode) must re-migrate rather than leave a dangling selection.
        let d = suite()
        let store = ProfileStore(defaults: d)
        store.selectedProfileID = UUID() // stale — no matching built-in or custom
        store.migrateIfNeeded(from: settings(d))
        XCTAssertNotNil(store.selectedProfile)
        XCTAssertEqual(store.selectedProfile?.name, "My Settings")
    }

    func testMigrationIsNoOpOnceSelected() {
        let d = suite()
        let s = settings(d)
        let store = ProfileStore(defaults: d)
        store.select(DictationProfile.instant.id)
        store.migrateIfNeeded(from: s)
        XCTAssertEqual(store.selectedProfileID, DictationProfile.instant.id)
        XCTAssertTrue(store.customProfiles.isEmpty)
    }

    func testShapeMatchDistinguishesLiveTypingFromInstant() {
        // Live Typing (instant + skip → cleanup off) must not match Instant (cleanup on).
        XCTAssertTrue(DictationProfile.liveTyping.shapeMatches(.liveTyping))
        XCTAssertFalse(DictationProfile.liveTyping.shapeMatches(.instant))
        XCTAssertFalse(DictationProfile.instant.shapeMatches(.liveTyping))
    }

    // MARK: first-run + delete

    func testFirstRunProfileForKeyChoice() {
        XCTAssertEqual(ProfileStore.firstRunProfile(forKeyChoice: .openAI).id, DictationProfile.instant.id)
        XCTAssertEqual(ProfileStore.firstRunProfile(forKeyChoice: .openRouter).id, DictationProfile.cheapestCloud.id)
        XCTAssertEqual(ProfileStore.firstRunProfile(forKeyChoice: .neither).id, DictationProfile.privateOffline.id)
    }

    func testDeleteCustomFallsBackToPrivateOffline() {
        let store = ProfileStore(defaults: suite())
        var custom = DictationProfile.instant; custom.id = UUID(); custom.name = "Tmp"; custom.builtIn = false
        store.add(custom)
        store.select(custom.id)
        store.delete(custom.id)
        XCTAssertTrue(store.customProfiles.isEmpty)
        XCTAssertEqual(store.selectedProfileID, DictationProfile.privateOffline.id)
    }

    func testSaveAsNewProfileCapturesSettingsAndSelects() {
        let d = suite()
        let s = settings(d)
        s.engineMode = "cloud"; s.cleanupLevel = "high"; s.cleanupProvider = "openai"
        let store = ProfileStore(defaults: d)
        let saved = store.saveAsNewProfile(named: "  Work  ", from: s)
        XCTAssertEqual(saved.name, "Work") // trimmed
        XCTAssertEqual(store.selectedProfileID, saved.id)
        XCTAssertEqual(store.selectedProfile?.cleanupLevel, "high")
        XCTAssertEqual(store.customProfiles.count, 1)
    }

    func testSaveAsDedupsDisplayNames() {
        let d = suite()
        let s = settings(d)
        let store = ProfileStore(defaults: d)
        let first = store.saveAsNewProfile(named: "Mine", from: s)
        let second = store.saveAsNewProfile(named: "Mine", from: s)
        XCTAssertEqual(first.name, "Mine")
        XCTAssertEqual(second.name, "Mine 2") // deduped
        XCTAssertNotEqual(first.id, second.id)
    }

    func testSaveCurrentSettingsUpdatesSelectedCustom() {
        let d = suite()
        let s = settings(d)
        let store = ProfileStore(defaults: d)
        let saved = store.saveAsNewProfile(named: "Mine", from: s)
        s.cleanupLevel = "medium" // fine-tune after saving
        store.saveCurrentSettingsToSelected(from: s)
        XCTAssertEqual(store.selectedProfile?.id, saved.id) // same profile id/name
        XCTAssertEqual(store.selectedProfile?.name, "Mine")
        XCTAssertEqual(store.selectedProfile?.cleanupLevel, "medium") // updated
        XCTAssertEqual(store.customProfiles.count, 1) // updated in place, not duplicated
    }

    func testSaveCurrentSettingsIsNoOpForBuiltIn() {
        let d = suite()
        let s = settings(d)
        let store = ProfileStore(defaults: d)
        store.select(DictationProfile.bestAccuracy.id) // a built-in
        s.cleanupLevel = "light"
        store.saveCurrentSettingsToSelected(from: s)
        XCTAssertTrue(store.customProfiles.isEmpty) // built-ins are immutable
        XCTAssertEqual(store.selectedProfileID, DictationProfile.bestAccuracy.id)
    }

    func testDeleteNonSelectedKeepsSelection() {
        let store = ProfileStore(defaults: suite())
        var a = DictationProfile.instant; a.id = UUID(); a.name = "A"; a.builtIn = false
        var b = DictationProfile.instant; b.id = UUID(); b.name = "B"; b.builtIn = false
        store.add(a); store.add(b)
        store.select(b.id)
        store.delete(a.id)
        XCTAssertEqual(store.selectedProfileID, b.id)
        XCTAssertEqual(store.customProfiles.map(\.name), ["B"])
    }
}
