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
}
