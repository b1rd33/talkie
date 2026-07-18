import XCTest
@testable import Talkie

final class VoiceActionProcessorTests: XCTestCase {
    func testNewLineAndParagraphCommandsBecomeWhitespace() {
        let result = VoiceActionProcessor.process(
            "First new line Second new paragraph Third", allowPressEnter: false)

        XCTAssertEqual(result.text, "First\nSecond\n\nThird")
        XCTAssertFalse(result.pressEnter)
    }

    func testPressEnterIsSuffixOnlyAndOptIn() {
        XCTAssertEqual(VoiceActionProcessor.process(
            "Send it press enter", allowPressEnter: true),
                       VoiceActionResult(text: "Send it", pressEnter: true))
        XCTAssertEqual(VoiceActionProcessor.process(
            "Tell them to press enter tomorrow", allowPressEnter: true),
                       VoiceActionResult(text: "Tell them to press enter tomorrow", pressEnter: false))
        XCTAssertEqual(VoiceActionProcessor.process(
            "Send it press enter", allowPressEnter: false),
                       VoiceActionResult(text: "Send it press enter", pressEnter: false))
    }
}
