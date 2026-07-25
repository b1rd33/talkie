import XCTest
@testable import Talkie

@MainActor
final class SimulatedAudioLevelSourceTests: XCTestCase {
    func testSameSeedProducesSameConversationFixture() {
        let a = SimulatedAudioLevelSource(seed: 42, fixture: .conversation)
        let b = SimulatedAudioLevelSource(seed: 42, fixture: .conversation)

        XCTAssertEqual((0..<120).map { a.level(atFrame: $0) },
                       (0..<120).map { b.level(atFrame: $0) })
    }

    func testDifferentSeedsProduceDifferentSpeech() {
        let a = SimulatedAudioLevelSource(seed: 1, fixture: .conversation)
        let b = SimulatedAudioLevelSource(seed: 2, fixture: .conversation)

        XCTAssertNotEqual((0..<60).map { a.level(atFrame: $0) },
                          (0..<60).map { b.level(atFrame: $0) })
    }

    func testEveryFixtureIsNormalized() {
        for fixture in SimulatedAudioFixture.allCases {
            let source = SimulatedAudioLevelSource(seed: 9, fixture: fixture)
            XCTAssertTrue((0..<300).allSatisfy { (0...1).contains(source.level(atFrame: $0)) },
                          fixture.rawValue)
        }
    }

    func testSilenceFixtureIsActuallyQuiet() {
        let source = SimulatedAudioLevelSource(seed: 9, fixture: .silence)
        XCTAssertLessThan((0..<120).map { source.level(atFrame: $0) }.max() ?? 1, 0.03)
    }
}
