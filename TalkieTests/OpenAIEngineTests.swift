import XCTest
@testable import Talkie

final class OpenAIEngineTests: XCTestCase {
    private final class PartialRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [String] = []

        func append(_ value: String) {
            lock.lock()
            storage.append(value)
            lock.unlock()
        }

        var values: [String] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
    }

    private var audioURL: URL!

    override func setUpWithError() throws {
        audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("fake-\(UUID().uuidString).m4a")
        try Data("fake-audio".utf8).write(to: audioURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: audioURL)
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    private func makeEngine(
        apiKey: String? = "sk-test",
        model: String = "gpt-transcribe",
        context: TranscriptionContext? = nil,
        stream: Bool = false
    ) -> OpenAIEngine {
        OpenAIEngine(apiKeyProvider: { apiKey }, modelProvider: { model },
                     contextProvider: { terms in
                         context ?? TranscriptionContext.build(
                             prompt: "", dictionaryTerms: terms, languageCodes: [])
                     },
                     streamProvider: { stream },
                     session: StubURLProtocol.session())
    }

    func testSendsMultipartRequestAndParsesText() async throws {
        var captured: URLRequest?
        var capturedBody: Data?
        StubURLProtocol.handler = { request in
            captured = request
            capturedBody = request.httpBody ?? request.bodyStreamData()
            let body = #"{"text":"hello world","languages":[{"code":"en"}]}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200,
                                    httpVersion: nil, headerFields: nil)!,
                    Data(body.utf8))
        }
        let result = try await makeEngine().transcribe(
            RecordedAudio(fileURL: audioURL, duration: 1.0), dictionaryTerms: ["Talkie"])

        XCTAssertEqual(result.text, "hello world")
        let request = try XCTUnwrap(captured)
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/audio/transcriptions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        let contentType = try XCTUnwrap(request.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary="))
        let body = try XCTUnwrap(capturedBody.flatMap { String(data: $0, encoding: .utf8) })
        XCTAssertTrue(body.contains("name=\"model\""))
        XCTAssertTrue(body.contains("\r\n\r\ngpt-transcribe\r\n"))
        XCTAssertTrue(body.contains("name=\"file\"; filename=\"audio.m4a\""))
        XCTAssertTrue(body.contains("name=\"keywords[]\""))
        XCTAssertTrue(body.contains("Talkie"))
        XCTAssertTrue(body.contains("fake-audio"))
        XCTAssertEqual(result.engineID, "gpt-transcribe")
        XCTAssertEqual(result.detectedLanguages, ["en"])
    }

    func testNewModelSendsPromptKeywordsAndMultipleLanguages() async throws {
        var capturedBody: Data?
        StubURLProtocol.handler = { request in
            capturedBody = request.httpBody ?? request.bodyStreamData()
            return (
                HTTPURLResponse(
                    url: request.url!, statusCode: 200,
                    httpVersion: nil, headerFields: nil)!,
                Data(#"{"text":"Hallo Talkie","languages":[{"code":"de"}]}"#.utf8))
        }
        let context = TranscriptionContext(
            prompt: "Product demo",
            keywords: ["Talkie"],
            languages: ["en", "de"])

        let result = try await makeEngine(context: context).transcribe(
            RecordedAudio(fileURL: audioURL, duration: 1.0),
            dictionaryTerms: ["ignored by explicit test context"])

        let body = try XCTUnwrap(
            capturedBody.flatMap { String(data: $0, encoding: .utf8) })
        XCTAssertTrue(body.contains("name=\"model\""))
        XCTAssertTrue(body.contains("\r\n\r\ngpt-transcribe\r\n"))
        XCTAssertTrue(body.contains("name=\"prompt\""))
        XCTAssertTrue(body.contains("\r\n\r\nProduct demo\r\n"))
        XCTAssertTrue(body.contains("name=\"keywords[]\""))
        XCTAssertTrue(body.contains("\r\n\r\nTalkie\r\n"))
        XCTAssertTrue(body.contains("name=\"languages[]\""))
        XCTAssertTrue(body.contains("\r\n\r\nen\r\n"))
        XCTAssertTrue(body.contains("\r\n\r\nde\r\n"))
        XCTAssertFalse(body.contains("name=\"language\""))
        XCTAssertEqual(result.text, "Hallo Talkie")
        XCTAssertEqual(result.engineID, "gpt-transcribe")
        XCTAssertEqual(result.detectedLanguages, ["de"])
    }

    func testMissingKeyThrows() async {
        do {
            _ = try await makeEngine(apiKey: nil).transcribe(
                RecordedAudio(fileURL: audioURL, duration: 1.0), dictionaryTerms: [])
            XCTFail("expected throw")
        } catch let error as EngineError {
            XCTAssertEqual(error, .missingAPIKey)
        } catch { XCTFail("wrong error: \(error)") }
    }

    func testLanguageFieldSentWhenPinned() async throws {
        var capturedBody: Data?
        StubURLProtocol.handler = { request in
            capturedBody = request.httpBody ?? request.bodyStreamData()
            return (HTTPURLResponse(url: request.url!, statusCode: 200,
                                    httpVersion: nil, headerFields: nil)!,
                    Data(#"{"text": "hallo welt"}"#.utf8))
        }
        let engine = OpenAIEngine(
            apiKeyProvider: { "sk-test" },
            modelProvider: { "gpt-4o-mini-transcribe" },
            contextProvider: { terms in
                TranscriptionContext(
                    prompt: "Legacy context",
                    keywords: terms,
                    languages: ["de"])
            },
            session: StubURLProtocol.session())
        _ = try await engine.transcribe(RecordedAudio(fileURL: audioURL, duration: 1.0),
                                        dictionaryTerms: ["Talkie"])
        let body = try XCTUnwrap(capturedBody.flatMap { String(data: $0, encoding: .utf8) })
        XCTAssertTrue(body.contains("name=\"language\""))
        XCTAssertTrue(body.contains("\r\n\r\nde\r\n"))
        XCTAssertTrue(body.contains("name=\"prompt\""))
        XCTAssertTrue(body.contains("Vocabulary: Talkie"))
        XCTAssertFalse(body.contains("name=\"keywords[]\""))
        XCTAssertFalse(body.contains("name=\"languages[]\""))
    }

    func testNoLanguageFieldByDefault() async throws {
        var capturedBody: Data?
        StubURLProtocol.handler = { request in
            capturedBody = request.httpBody ?? request.bodyStreamData()
            return (HTTPURLResponse(url: request.url!, statusCode: 200,
                                    httpVersion: nil, headerFields: nil)!,
                    Data(#"{"text": "hello"}"#.utf8))
        }
        _ = try await makeEngine().transcribe(RecordedAudio(fileURL: audioURL, duration: 1.0),
                                              dictionaryTerms: [])
        let body = try XCTUnwrap(capturedBody.flatMap { String(data: $0, encoding: .utf8) })
        XCTAssertFalse(body.contains("name=\"language\""))
    }

    func testEmptyCompletedResponseFailsClosed() async {
        StubURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200,
                             httpVersion: nil, headerFields: nil)!,
             Data(#"{"text":"   "}"#.utf8))
        }

        do {
            _ = try await makeEngine().transcribe(
                RecordedAudio(fileURL: audioURL, duration: 1.0), dictionaryTerms: [])
            XCTFail("expected an empty transcription failure")
        } catch let error as EngineError {
            XCTAssertEqual(error, .emptyTranscription)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testStreamsCompletedFileProgressAndRequiresFinalEvent() async throws {
        var capturedBody: Data?
        StubURLProtocol.handler = { request in
            capturedBody = request.httpBody ?? request.bodyStreamData()
            let body = """
            data: {"type":"transcript.text.delta","delta":"Hel"}

            data: {"type":"transcript.text.delta","delta":"lo"}

            data: {"type":"transcript.text.done","text":"Hello","languages":[{"code":"en"}]}


            """
            return (
                HTTPURLResponse(
                    url: request.url!, statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "text/event-stream"])!,
                Data(body.utf8))
        }
        let partials = PartialRecorder()

        let result = try await makeEngine(stream: true).transcribe(
            RecordedAudio(fileURL: audioURL, duration: 1.0),
            dictionaryTerms: [],
            onPartial: { partials.append($0) })

        let requestBody = try XCTUnwrap(
            capturedBody.flatMap { String(data: $0, encoding: .utf8) })
        XCTAssertTrue(requestBody.contains("name=\"stream\""))
        XCTAssertTrue(requestBody.contains("\r\n\r\ntrue\r\n"))
        XCTAssertEqual(partials.values, ["Hel", "Hello"])
        XCTAssertEqual(result.text, "Hello")
        XCTAssertEqual(result.detectedLanguages, ["en"])
    }

    func testStreamWithoutFinalEventFails() async {
        StubURLProtocol.handler = { request in
            (
                HTTPURLResponse(
                    url: request.url!, statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "text/event-stream"])!,
                Data("""
                data: {"type":"transcript.text.delta","delta":"partial"}


                """.utf8))
        }

        do {
            _ = try await makeEngine(stream: true).transcribe(
                RecordedAudio(fileURL: audioURL, duration: 1.0),
                dictionaryTerms: [])
            XCTFail("expected a missing-final-event failure")
        } catch let error as EngineError {
            XCTAssertEqual(error, .invalidResponse)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testEmptyStreamedCompletionFailsClosed() async {
        StubURLProtocol.handler = { request in
            (
                HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: nil,
                    headerFields: ["Content-Type": "text/event-stream"])!,
                Data("data: {\"type\":\"transcript.text.done\",\"text\":\" \"}\n\n".utf8))
        }

        do {
            _ = try await makeEngine(stream: true).transcribe(
                RecordedAudio(fileURL: audioURL, duration: 1.0), dictionaryTerms: [])
            XCTFail("expected an empty streamed transcription failure")
        } catch let error as EngineError {
            XCTAssertEqual(error, .emptyTranscription)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testOfflineErrorMapsToOfflineCase() async {
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await makeEngine().transcribe(
                RecordedAudio(fileURL: audioURL, duration: 1.0), dictionaryTerms: [])
            XCTFail("expected throw")
        } catch let error as EngineError {
            XCTAssertEqual(error, .offline)
        } catch { XCTFail("wrong error: \(error)") }
    }

    func testHTTPErrorSurfacesStatusAndBody() async {
        StubURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!,
             Data(#"{"error": {"message": "bad key"}}"#.utf8))
        }
        do {
            _ = try await makeEngine().transcribe(
                RecordedAudio(fileURL: audioURL, duration: 1.0), dictionaryTerms: [])
            XCTFail("expected throw")
        } catch let error as EngineError {
            guard case .requestFailed(let status, let message) = error else {
                return XCTFail("wrong case: \(error)")
            }
            XCTAssertEqual(status, 401)
            XCTAssertTrue(message.contains("bad key"))
        } catch { XCTFail("wrong error: \(error)") }
    }
}
