import XCTest
@testable import Talkie

@MainActor
final class HistoryStoreTests: XCTestCase {
    private func makeStore() throws -> HistoryStore {
        try HistoryStore(inMemory: true)
    }

    func testSaveAndFetchRecent() throws {
        let store = try makeStore()
        store.save(rawText: "raw", cleanedText: "clean", appBundleID: "com.apple.TextEdit",
                   appName: "TextEdit", duration: 2.5, engine: "openai", status: .completed)
        let recent = store.recent(limit: 10)
        XCTAssertEqual(recent.count, 1)
        XCTAssertEqual(recent[0].cleanedText, "clean")
        XCTAssertEqual(recent[0].status, .completed)
        XCTAssertEqual(recent[0].wordCount, 1)
    }

    func testRecentIsNewestFirstAndLimited() throws {
        let store = try makeStore()
        for i in 0..<5 {
            store.save(rawText: "r\(i)", cleanedText: "c\(i)", appBundleID: nil, appName: nil,
                       duration: 1, engine: "openai", status: .completed)
        }
        let recent = store.recent(limit: 3)
        XCTAssertEqual(recent.count, 3)
        XCTAssertEqual(recent[0].cleanedText, "c4")
    }

    func testDelete() throws {
        let store = try makeStore()
        store.save(rawText: "r", cleanedText: "c", appBundleID: nil, appName: nil,
                   duration: 1, engine: "openai", status: .cancelled)
        store.delete(store.recent(limit: 1)[0])
        XCTAssertTrue(store.recent(limit: 10).isEmpty)
    }

    func testDictionaryCRUD() throws {
        let store = try makeStore()
        store.addTerm("Archiev", soundsLike: "ar-keev")
        store.addTerm("Talkie")
        XCTAssertEqual(store.dictionaryTermStrings(), ["Archiev", "Talkie"]) // sorted by term
        let entry = store.allTerms()[0]
        XCTAssertEqual(entry.soundsLike, "ar-keev")
        store.updateTerm(entry, term: "Archiev GmbH", soundsLike: nil)
        XCTAssertEqual(store.allTerms().map(\.term), ["Archiev GmbH", "Talkie"])
        XCTAssertNil(store.allTerms()[0].soundsLike)
        store.deleteTerm(store.allTerms()[0])
        XCTAssertEqual(store.dictionaryTermStrings(), ["Talkie"])
    }

    func testBlankTermIgnored() throws {
        let store = try makeStore()
        store.addTerm("   ")
        XCTAssertTrue(store.allTerms().isEmpty)
    }

    func testStyleOverrideUpsertAndRemove() throws {
        let store = try makeStore()
        store.setStyleOverride(bundleID: "com.apple.dt.Xcode", preset: .casual)
        store.setStyleOverride(bundleID: "com.apple.dt.Xcode", preset: .polished) // upsert, no duplicate
        XCTAssertEqual(store.styleOverridesByBundleID(), ["com.apple.dt.Xcode": "polished"])
        XCTAssertEqual(store.allStyleOverrides().count, 1)
        store.removeStyleOverride(bundleID: "com.apple.dt.Xcode")
        XCTAssertTrue(store.styleOverridesByBundleID().isEmpty)
    }

    func testStatsCountCompletedOnly() throws {
        let store = try makeStore()
        store.save(rawText: "r", cleanedText: "one two three", appBundleID: nil, appName: nil,
                   duration: 60, engine: "openai", status: .completed)
        store.save(rawText: "r", cleanedText: "four five", appBundleID: nil, appName: nil,
                   duration: 30, engine: "openai", status: .completed)
        store.save(rawText: "r", cleanedText: "ignored words here", appBundleID: nil, appName: nil,
                   duration: 10, engine: "openai", status: .failed)
        let stats = store.stats()
        XCTAssertEqual(stats.totalWords, 5)
        XCTAssertEqual(stats.totalDuration, 90)
        XCTAssertEqual(stats.dictationsToday, 2) // save() stamps Date() — today
    }

    func testStreakCountsConsecutiveDaysEndingToday() throws {
        let store = try makeStore()
        XCTAssertEqual(store.stats().streakDays, 0)
        for text in ["one", "two", "three"] {
            store.save(rawText: "r", cleanedText: text, appBundleID: nil, appName: nil,
                       duration: 1, engine: "openai", status: .completed)
        }
        let records = store.recent(limit: 3) // backdate two — save() stamps Date()
        records[0].date = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        records[1].date = Calendar.current.date(byAdding: .day, value: -3, to: Date())! // gap breaks the streak
        XCTAssertEqual(store.stats().streakDays, 2) // today + yesterday
    }

    func testSaveStampsMetadataAndAudioPath() throws {
        let store = try makeStore()
        // Param order matches the accreted Phase 2+3 signature: cleanupModel, language, audioPath.
        store.save(rawText: "r", cleanedText: "", appBundleID: nil, appName: nil,
                   duration: 5, engine: "openai", status: .failed,
                   cleanupModel: "google/gemini-2.5-flash", language: "German",
                   audioPath: "/tmp/talkie-keep.m4a")
        let record = store.recent(limit: 1)[0]
        XCTAssertEqual(record.language, "German")
        XCTAssertEqual(record.cleanupModel, "google/gemini-2.5-flash")
        XCTAssertEqual(record.audioPath, "/tmp/talkie-keep.m4a")
    }

    func testMarkRetriedCompletesRecordAndClearsAudioPath() throws {
        let store = try makeStore()
        store.save(rawText: "", cleanedText: "", appBundleID: nil, appName: nil,
                   duration: 5, engine: "openai", status: .failed, audioPath: "/tmp/keep.m4a")
        let record = store.recent(limit: 1)[0]
        store.markRetried(record, rawText: "raw", cleanedText: "Clean text.")
        XCTAssertEqual(record.status, .completed)
        XCTAssertEqual(record.cleanedText, "Clean text.")
        XCTAssertEqual(record.wordCount, 2)
        XCTAssertNil(record.audioPath)
    }
}
