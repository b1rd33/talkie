import XCTest
@testable import Talkie

final class PillPresentationTests: XCTestCase {
    func testRecordingPresentationCarriesLevelAndWarnings() {
        let value = PillPresentation(
            state: .recording(handsFree: false),
            style: .frostedGlass,
            elapsed: 4,
            audioLevel: 0.42,
            errorMessage: nil,
            offline: true,
            cleanupDegraded: false,
            reduceMotion: false,
            increasedContrast: false)

        XCTAssertNil(value.statusLabel)
        XCTAssertTrue(value.isActive)
        XCTAssertEqual(value.audioLevel, 0.42)
        XCTAssertEqual(value.accessibilityLabel, "Recording, 4 seconds, offline mode")
    }

    func testProcessingStatesShareOneVisualPhase() {
        XCTAssertEqual(PillPresentation.preview(.transcribing).visualPhase, .processing)
        XCTAssertEqual(PillPresentation.preview(.cleaning).visualPhase, .processing)
        XCTAssertEqual(PillPresentation.preview(.inserting).visualPhase, .processing)
    }

    func testProcessingStatesNeverExposeVisualText() {
        for state in [PillPresentation.State.transcribing, .cleaning, .inserting] {
            XCTAssertNil(PillPresentation.preview(state).statusLabel)
        }
    }

    func testTimerAndVisibleCancelAreIndependentOptInFlags() {
        var value = PillPresentation.preview(.recording(handsFree: false))
        XCTAssertFalse(value.showsTimer)
        XCTAssertFalse(value.showsCancelButton)

        value.showsTimer = true
        XCTAssertTrue(value.showsTimer)
        XCTAssertFalse(value.showsCancelButton)

        value.showsCancelButton = true
        XCTAssertTrue(value.showsTimer)
        XCTAssertTrue(value.showsCancelButton)
    }

    func testNonProcessingStatesHaveDistinctVisualPhases() {
        XCTAssertEqual(PillPresentation.preview(.idle).visualPhase, .idle)
        XCTAssertEqual(PillPresentation.preview(.recording(handsFree: false)).visualPhase,
                       .recording)
        XCTAssertEqual(PillPresentation.preview(.success).visualPhase, .success)
        XCTAssertEqual(PillPresentation.preview(.error).visualPhase, .error)
    }

    func testPrivacySafeAccessibilityLabelsNeverContainErrorDetails() {
        let value = PillPresentation.preview(.error, errorMessage: "secret provider response")

        XCTAssertEqual(value.accessibilityLabel, "Dictation failed")
        XCTAssertFalse(value.accessibilityLabel.contains("secret"))
    }

    func testPreviewDefaultsAreDeterministic() {
        XCTAssertEqual(PillPresentation.preview(.idle), PillPresentation.preview(.idle))
        XCTAssertEqual(PillPresentation.preview(.recording(handsFree: true)).elapsed, 4)
    }

    func testProductionStateMappingPreservesHandsFreeAndError() {
        XCTAssertEqual(PillPresentation.State.map(.recording, handsFree: true),
                       .recording(handsFree: true))
        XCTAssertEqual(PillPresentation.State.map(.cleaning, handsFree: false), .cleaning)
        XCTAssertEqual(PillPresentation.State.map(.error("network"), handsFree: false), .error)
    }

    func testSuccessOverridesIdleOnly() {
        XCTAssertEqual(PillPresentation.State.map(.idle, handsFree: false, showSuccess: true), .success)
        XCTAssertEqual(PillPresentation.State.map(.recording, handsFree: false, showSuccess: true),
                       .recording(handsFree: false))
    }

    func testOnlyStatesWithVisibleCancelControlAreCancellable() {
        XCTAssertTrue(PillPresentation.preview(.recording(handsFree: false)).isCancellable)
        XCTAssertTrue(PillPresentation.preview(.transcribing).isCancellable)
        XCTAssertTrue(PillPresentation.preview(.cleaning).isCancellable)
        XCTAssertTrue(PillPresentation.preview(.inserting).isCancellable)
        XCTAssertFalse(PillPresentation.preview(.idle).isCancellable)
        XCTAssertFalse(PillPresentation.preview(.success).isCancellable)
        XCTAssertFalse(PillPresentation.preview(.error).isCancellable)
    }
}
