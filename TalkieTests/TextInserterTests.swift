import XCTest
@testable import Talkie

@MainActor
final class TextInserterTests: XCTestCase {
    final class MockNotifier: Notifying {
        var messages: [String] = []
        func notify(title: String, body: String) { messages.append(title) }
    }

    final class MockPasteboardGuard: PasteboardGuarding {
        var writes: [String] = []
        var restoreCount = 0

        func snapshotAndWrite(_ text: String) { writes.append(text) }
        func restoreIfUnchanged() { restoreCount += 1 }
    }

    private func makeInserter(secureInput: Bool = false, axTrusted: Bool = true,
                              notifier: MockNotifier? = nil)
    -> (TextInserter, MockNotifier, () -> Int) {
        // MockNotifier conforms to a @MainActor protocol, so its init can't run in
        // nonisolated default-argument position (same workaround as makeCoordinator).
        let notifier = notifier ?? MockNotifier()
        var pastes = 0
        let inserter = TextInserter(pasteKeystroke: { pastes += 1; return true },
                                    secureInputCheck: { secureInput },
                                    axTrustedCheck: { axTrusted },
                                    notifier: notifier,
                                    restoreDelay: .milliseconds(1))
        return (inserter, notifier, { pastes })
    }

    func testInsertsViaPasteAndRestores() async throws {
        let guard_ = MockPasteboardGuard()
        var pastes = 0
        let inserter = TextInserter(pasteKeystroke: { pastes += 1; return true },
                                    secureInputCheck: { false },
                                    axTrustedCheck: { true },
                                    pasteboardGuard: guard_,
                                    restoreDelay: .milliseconds(1))
        try await inserter.insert("Hello from Talkie")
        XCTAssertEqual(pastes, 1)
        XCTAssertEqual(guard_.writes, ["Hello from Talkie"])
        XCTAssertEqual(guard_.restoreCount, 1)
    }

    func testEmptyTextDoesNothing() async throws {
        let (inserter, _, pastes) = makeInserter()
        try await inserter.insert("   ")
        XCTAssertEqual(pastes(), 0)
    }

    func testSecureInputRefusesAndThrows() async {
        let (inserter, notifier, pastes) = makeInserter(secureInput: true)
        do {
            try await inserter.insert("secret")
            XCTFail("expected throw")
        } catch let error as InsertionError {
            XCTAssertEqual(error, .secureInputActive)
        } catch { XCTFail("wrong error: \(error)") }
        XCTAssertEqual(pastes(), 0)
        XCTAssertEqual(notifier.messages.count, 1)
    }

    func testNoAccessibilityFallsBackToClipboardOnly() async throws {
        let (inserter, notifier, pastes) = makeInserter(axTrusted: false)
        try await inserter.insert("fallback text")
        XCTAssertEqual(pastes(), 0) // no keystroke without AX trust
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "fallback text")
        XCTAssertEqual(notifier.messages.count, 1) // "Copied — press ⌘V"
    }
}
