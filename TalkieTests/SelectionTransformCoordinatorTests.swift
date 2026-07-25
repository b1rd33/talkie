import XCTest
@testable import Talkie

@MainActor
final class SelectionTransformCoordinatorTests: XCTestCase {
    final class Transformer: SelectionTransforming, @unchecked Sendable {
        var calls: [(String, String)] = []
        var result = "Rewritten"
        func transform(_ text: String, instruction: String) async throws -> String {
            calls.append((text, instruction)); return result
        }
    }

    func testPreviewApplyRetryAndUndoRetainOriginalOnlyForActiveFlow() async {
        var field = "Original"
        let target = SelectionTarget(originalText: field) { replacement in
            field = replacement; return true
        }
        let transformer = Transformer()
        let coordinator = SelectionTransformCoordinator(transformer: transformer)
        coordinator.capture(target)

        await coordinator.preview(instruction: "Make concise")
        XCTAssertEqual(coordinator.preview?.original, "Original")
        XCTAssertEqual(coordinator.preview?.transformed, "Rewritten")
        XCTAssertFalse(coordinator.undo(), "Undo must not edit the field before Apply")
        XCTAssertTrue(coordinator.apply())
        XCTAssertTrue(coordinator.wasApplied)
        XCTAssertEqual(field, "Rewritten")

        transformer.result = "Shorter"
        await coordinator.retry()
        XCTAssertEqual(coordinator.preview?.transformed, "Shorter")
        XCTAssertTrue(coordinator.undo())
        XCTAssertEqual(field, "Original")
        XCTAssertNil(coordinator.preview)
        XCTAssertFalse(coordinator.wasApplied)
    }

    func testEmptySelectionCannotStartFlow() {
        let coordinator = SelectionTransformCoordinator(transformer: Transformer())
        coordinator.capture(SelectionTarget(originalText: "   ") { _ in true })
        XCTAssertNil(coordinator.preview)
        XCTAssertFalse(coordinator.apply())
    }
}
