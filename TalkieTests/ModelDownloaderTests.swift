import XCTest
@testable import Talkie

@MainActor
final class ModelDownloaderTests: XCTestCase {
    func testStateTransitionsOnSuccess() async {
        let downloader = ModelDownloader(fetch: { progress in
            progress(0.5)
            progress(1.0)
        })
        XCTAssertEqual(downloader.state, .idle)
        await downloader.download()
        XCTAssertEqual(downloader.state, .ready)
        XCTAssertEqual(downloader.progress, 1.0)
    }

    func testFailureCapturesMessage() async {
        let downloader = ModelDownloader(fetch: { _ in
            throw EngineError.requestFailed(status: 0, message: "disk full")
        })
        await downloader.download()
        guard case .failed(let message) = downloader.state else { return XCTFail("expected failed") }
        XCTAssertTrue(message.contains("disk full"))
    }

    func testConcurrentDownloadIgnored() async {
        var calls = 0
        let downloader = ModelDownloader(fetch: { _ in
            calls += 1
            try await Task.sleep(for: .milliseconds(50))
        })
        async let first: Void = downloader.download()
        async let second: Void = downloader.download() // ignored while .downloading
        _ = await (first, second)
        XCTAssertEqual(calls, 1)
    }
}
