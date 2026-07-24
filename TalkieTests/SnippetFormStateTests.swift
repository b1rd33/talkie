import XCTest
@testable import Talkie

final class SnippetFormStateTests: XCTestCase {
    func testEditingTriggerClearsExistingError() {
        var form = SnippetFormState()
        form.errorMessage = "That trigger already exists."

        form.trigger = "different trigger"

        XCTAssertNil(form.errorMessage)
    }

    func testEditingExpansionClearsExistingError() {
        var form = SnippetFormState()
        form.errorMessage = "That trigger already exists."

        form.expansion = "Different expansion"

        XCTAssertNil(form.errorMessage)
    }

    func testDeleteAccessibilityLabelNamesSnippet() {
        XCTAssertEqual(
            SnippetFormState.deleteAccessibilityLabel(trigger: "codex test snippet"),
            "Delete snippet codex test snippet"
        )
    }
}
