import XCTest
@testable import Talkie

final class SpeakerReferenceStoreTests: XCTestCase {
    func testSavesReferenceLocallyAndRemovesIt() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("speaker-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.m4a")
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true)
        try Data("voice".utf8).write(to: source)
        let store = SpeakerReferenceStore(baseDirectory: root)

        try store.save(RecordedAudio(fileURL: source, duration: 5))

        XCTAssertTrue(store.hasReference)
        XCTAssertEqual(
            try store.configuration().speakerName,
            SpeakerFilterConfiguration.enrolledSpeakerName)
        let attributes = try FileManager.default.attributesOfItem(
            atPath: store.referenceURL.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)

        try store.remove()
        XCTAssertFalse(store.hasReference)
    }

    func testRejectsReferenceOutsideOpenAILimits() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("speaker-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source.m4a")
        try Data("voice".utf8).write(to: source)
        let store = SpeakerReferenceStore(baseDirectory: root)

        XCTAssertThrowsError(try store.save(
            RecordedAudio(fileURL: source, duration: 1.9))) {
            XCTAssertEqual($0 as? SpeakerReferenceError, .tooShort)
        }
        XCTAssertThrowsError(try store.save(
            RecordedAudio(fileURL: source, duration: 10.1))) {
            XCTAssertEqual($0 as? SpeakerReferenceError, .tooLong)
        }
    }
}
