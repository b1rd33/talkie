import XCTest
@testable import Talkie

final class DictationProfileTests: XCTestCase {

    // MARK: requiredKey

    func testRequiredKeyPerBuiltIn() {
        XCTAssertEqual(DictationProfile.privateOffline.requiredKey, .none)
        XCTAssertEqual(DictationProfile.liveTyping.requiredKey, .openAI)
        XCTAssertEqual(DictationProfile.instant.requiredKey, .openAI)
        XCTAssertEqual(DictationProfile.bestAccuracy.requiredKey, .openAI)
        XCTAssertEqual(DictationProfile.cheapestCloud.requiredKey, .openRouter)
    }

    func testRequiredKeyBothForOpenAITranscribePlusOpenRouterCleanup() {
        // The shipping two-key default → migrates to a "My Settings" profile = .both.
        let p = DictationProfile(
            id: UUID(), name: "My Settings", builtIn: false,
            engineMode: "cloud", instantSkipCleanup: false, instantLiveType: false,
            transcriptionProvider: "openai", transcriptionModel: "gpt-4o-mini-transcribe",
            openrouterTranscriptionModel: "mistralai/voxtral-mini-transcribe",
            cleanupLevel: "high", cleanupProvider: "openrouter",
            cleanupModel: "google/gemini-2.5-flash-lite", customCleanupPrompt: "")
        XCTAssertEqual(p.requiredKey, .both)
    }

    func testRequiredKeySkipCleanupDropsCleanupKey() {
        // instant + skip-cleanup → cleanup doesn't run → only the transcription key.
        var p = DictationProfile.instant
        p.instantSkipCleanup = true
        p.cleanupProvider = "openrouter" // would add openRouter IF cleanup ran
        XCTAssertEqual(p.requiredKey, .openAI) // cleanup skipped, so no openRouter
    }

    // MARK: apply write-order (instantLiveType didSet force-sets instantSkipCleanup)

    private func freshStore() -> SettingsStore {
        SettingsStore(defaults: UserDefaults(suiteName: "talkie-profile-tests-\(UUID().uuidString)")!)
    }

    func testApplyLiveTypingForcesSkipCleanup() {
        let s = freshStore()
        DictationProfile.liveTyping.apply(to: s)
        XCTAssertEqual(s.engineMode, "instant")
        XCTAssertTrue(s.instantLiveType)
        XCTAssertTrue(s.instantSkipCleanup) // forced by instantLiveType didSet
    }

    func testApplyInstantKeepsSkipFalseEvenAfterLiveType() {
        // Write-order hazard: applying a non-live-type profile after a live-type one
        // must leave instantSkipCleanup false (instantLiveType written LAST as false).
        let s = freshStore()
        DictationProfile.liveTyping.apply(to: s) // store now has liveType=true, skip=true
        DictationProfile.instant.apply(to: s)    // instant: liveType=false, skip=false
        XCTAssertFalse(s.instantLiveType)
        XCTAssertFalse(s.instantSkipCleanup)
        XCTAssertEqual(s.cleanupLevel, "medium")
        XCTAssertEqual(s.cleanupProvider, "openai")
    }

    func testApplyWritesAllPipelineFields() {
        let s = freshStore()
        DictationProfile.cheapestCloud.apply(to: s)
        XCTAssertEqual(s.engineMode, "cloud")
        XCTAssertEqual(s.transcriptionProvider, "openrouter")
        XCTAssertEqual(s.cleanupProvider, "openrouter")
        XCTAssertEqual(s.cleanupModel, "google/gemini-2.5-flash-lite")
    }

    // MARK: preset membership (no built-in pins a typo'd / retired model)

    func testBuiltInModelsAreKnownPresets() {
        for p in DictationProfile.builtIns {
            XCTAssertTrue(ModelPresets.transcription.contains(p.transcriptionModel),
                          "\(p.name): transcriptionModel \(p.transcriptionModel) not a known preset")
            XCTAssertTrue(ModelPresets.openrouterTranscription.contains(p.openrouterTranscriptionModel),
                          "\(p.name): openrouterTranscriptionModel \(p.openrouterTranscriptionModel) not a known preset")
            let cleanupPresets = p.cleanupProvider == "openai" ? ModelPresets.openaiCleanup : ModelPresets.openrouterCleanup
            XCTAssertTrue(cleanupPresets.contains(p.cleanupModel),
                          "\(p.name): cleanupModel \(p.cleanupModel) not a known \(p.cleanupProvider) preset")
        }
    }

    func testBuiltInsHaveStableUniqueIDs() {
        let ids = DictationProfile.builtIns.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count) // unique
        XCTAssertTrue(DictationProfile.builtIns.allSatisfy(\.builtIn))
    }

    func testSamePipelineIgnoresIdentityButTracksFields() {
        var a = DictationProfile.instant
        var b = DictationProfile.instant
        b.id = UUID(); b.name = "Copy"; b.builtIn = false
        XCTAssertTrue(a.samePipeline(as: b)) // identity differs, pipeline identical
        b.cleanupLevel = "high"
        XCTAssertFalse(a.samePipeline(as: b)) // a pipeline field differs
    }

    func testSimpleDescriptionDistinctForBuiltInsGenericForCustom() {
        for p in DictationProfile.builtIns {
            XCTAssertFalse(p.simpleDescription.isEmpty)
            XCTAssertNotEqual(p.simpleDescription, "Your custom settings.")
        }
        var custom = DictationProfile.instant
        custom.id = UUID(); custom.builtIn = false
        XCTAssertEqual(custom.simpleDescription, "Your custom settings.")
    }

    func testDisplaySummaryIsSelfContainedAndDistinct() {
        // Built-ins: name + their description; all rows distinct.
        let summaries = DictationProfile.builtIns.map(\.displaySummary)
        XCTAssertEqual(Set(summaries).count, summaries.count) // no two rows identical
        XCTAssertTrue(DictationProfile.instant.displaySummary.contains("Instant"))
        XCTAssertTrue(DictationProfile.instant.displaySummary.contains("—")) // has a detail
        // Custom: marked (custom) + shows the key it needs.
        var custom = DictationProfile.bestAccuracy
        custom.id = UUID(); custom.name = "Work"; custom.builtIn = false
        XCTAssertTrue(custom.displaySummary.contains("Work (custom)"))
        XCTAssertTrue(custom.displaySummary.contains("needs OpenAI"))
    }

    func testCodableRoundTrip() throws {
        let data = try JSONEncoder().encode(DictationProfile.bestAccuracy)
        let decoded = try JSONDecoder().decode(DictationProfile.self, from: data)
        XCTAssertEqual(decoded, DictationProfile.bestAccuracy)
    }
}
