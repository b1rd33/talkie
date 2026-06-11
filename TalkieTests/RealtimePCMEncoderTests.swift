import XCTest
@testable import Talkie

final class RealtimePCMEncoderTests: XCTestCase {
    func testResamplesAndWidens() throws {
        let encoder = RealtimePCMEncoder() // 16_000 → 24_000 default
        let input = [Float](repeating: 0.5, count: 1600) // 100ms @ 16k
        let data = try encoder.encode(input)
        // 100ms @ 24k = 2400 frames × 2 bytes ≈ 4800 bytes (resampler priming ±64 frames)
        XCTAssertEqual(Double(data.count), 4800, accuracy: 256)
        // pcm16 little-endian: amplitude ~0.5 → ~16384
        // & ~1 forces an even offset: data.count / 2 equals the resampler's frame count, which may be
        // odd — an odd offset both traps load's alignment precondition and straddles a sample boundary
        let sample = data.withUnsafeBytes { $0.load(fromByteOffset: (data.count / 2) & ~1, as: Int16.self) }
        XCTAssertEqual(Double(sample), 16384, accuracy: 1500)
    }

    func testFlushDrainsResamplerTail() throws {
        let encoder = RealtimePCMEncoder()
        _ = try encoder.encode([Float](repeating: 0.3, count: 1600))
        let tail = try encoder.flush()
        XCTAssertGreaterThan(tail.count, 0) // the polyphase filter holds back some frames
    }

    func testClampsOutOfRange() throws {
        let encoder = RealtimePCMEncoder(inputRate: 24_000, outputRate: 24_000) // passthrough rate
        let data = try encoder.encode([2.0, -2.0])
        let first = data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: Int16.self) }
        let second = data.withUnsafeBytes { $0.load(fromByteOffset: 2, as: Int16.self) }
        XCTAssertEqual(first, Int16.max)
        XCTAssertEqual(second, -32767) // symmetric scaling: Int16(-1.0 × 32767) — NOT Int16.min
    }
}
