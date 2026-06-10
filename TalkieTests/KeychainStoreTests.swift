import XCTest
@testable import Talkie

final class KeychainStoreTests: XCTestCase {
    // Separate service name so tests never touch real keys.
    private let store = KeychainStore(service: "com.archiev.talkie.tests")

    override func tearDown() {
        store.delete(.openAIKey)
        store.delete(.openRouterKey)
        super.tearDown()
    }

    func testReadMissingReturnsNil() {
        XCTAssertNil(store.read(.openAIKey))
    }

    func testWriteThenRead() {
        XCTAssertEqual(store.write("sk-test-123", for: .openAIKey), errSecSuccess)
        XCTAssertEqual(store.read(.openAIKey), "sk-test-123")
    }

    func testOverwrite() {
        store.write("first", for: .openAIKey)
        store.write("second", for: .openAIKey)
        XCTAssertEqual(store.read(.openAIKey), "second")
    }

    func testDelete() {
        store.write("gone", for: .openAIKey)
        store.delete(.openAIKey)
        XCTAssertNil(store.read(.openAIKey))
    }
}
