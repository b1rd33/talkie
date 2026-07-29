# OpenAI Transcription Models Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `gpt-transcribe` and `gpt-live-transcribe` Talkie's default OpenAI transcription paths and expose their context, language, latency, streaming, detected-language, pricing, and fallback behavior without changing local or OpenRouter transcription.

**Architecture:** Add a small capability catalog and a privacy-safe transcription-context value, then let the batch and Realtime encoders select fields from those capabilities. Keep existing engine boundaries, route partial batch SSE text through an optional progress interface, and store detected languages separately from the configured output language.

**Tech Stack:** Swift 5.10, SwiftUI, URLSession multipart/SSE, URLSessionWebSocketTask, SwiftData, XCTest, XcodeGen, Bash, GitHub Actions.

---

## Source contract and scope

Implement against the approved design in
`docs/superpowers/specs/2026-07-29-openai-transcription-models-design.md`.
The official source pages are:

- `https://developers.openai.com/api/docs/guides/transcription`
- `https://developers.openai.com/api/docs/guides/speech-to-text`
- `https://developers.openai.com/api/docs/guides/realtime-transcription`
- `https://developers.openai.com/api/docs/models/gpt-transcribe`
- `https://developers.openai.com/api/docs/models/gpt-live-transcribe`
- `https://developers.openai.com/api/docs/pricing`

Do not infer undocumented limits. Keep tests deterministic and never call a live
provider from `xcodebuild test`.

## File map

**Create**

- `Talkie/Core/Engines/OpenAITranscriptionModel.swift` — model workflow,
  capabilities, display metadata, legacy status, and documented prices.
- `Talkie/Core/Engines/TranscriptionContext.swift` — normalized prompt, keywords,
  expected languages, and model-aware field selection.
- `Talkie/Core/Engines/OpenAISSEParser.swift` — incremental parser for completed-file
  transcription SSE events.
- `TalkieTests/OpenAITranscriptionModelTests.swift` — catalog and capability tests.
- `TalkieTests/TranscriptionContextTests.swift` — normalization and privacy boundary
  tests.
- `TalkieTests/OpenAISSEParserTests.swift` — fragmented/multiple/malformed SSE tests.

**Modify**

- `Talkie/Data/ModelPresets.swift` — separate batch and Realtime preset lists.
- `Talkie/Data/SettingsStore.swift` — new defaults, fields, and migration.
- `Talkie/Data/SupportedLanguages.swift` — validated OpenAI hint-code mapping.
- `Talkie/Data/DictationProfile.swift` — new built-in model defaults.
- `Talkie/Core/Engines/TranscriptionEngine.swift` — detected languages and optional
  progress sink.
- `Talkie/Core/Engines/OpenAIEngine.swift` — capability-aware multipart/JSON/SSE.
- `Talkie/Core/Engines/Realtime/RealtimeEvents.swift` — new session context and delay
  fields plus optional detected languages.
- `Talkie/Core/Engines/Realtime/OpenAIRealtimeSession.swift` — model-aware context,
  delay, metadata, and model-specific engine ID.
- `Talkie/Core/Engines/EngineRouter.swift` — pass partial progress without changing
  local/OpenRouter behavior.
- `Talkie/Core/Engines/OpenRouterTranscriptionEngine.swift` — accept and ignore the
  optional OpenAI batch-progress sink.
- `Talkie/Core/Engines/ParakeetEngine.swift` — accept and ignore the optional cloud
  progress sink.
- `Talkie/App/AppDelegate.swift` — settings/context providers and new live factory.
- `Talkie/Core/PriceBook.swift` — documented rates and model-specific history costs.
- `Talkie/Data/DictationRecord.swift` — separately persisted detected language codes.
- `Talkie/Data/HistoryStore.swift` — save detected language codes.
- `Talkie/Core/DictationCoordinator.swift` — batch partial preview and metadata save.
- `Talkie/UI/Hub/SettingsView.swift` — advanced model/context/language/latency UI.
- `Talkie/UI/Hub/SimpleSettingsView.swift` — concise model/language summary.
- `Talkie/UI/Hub/HistoryView.swift` — detected language badge.
- Existing tests named in each task below.
- `scripts/live-verify.sh` — opt-in JSON, SSE, and Realtime smoke checks.
- `docs/testing-matrix.md`, `README.md`, `CONTRIBUTING.md` — behavior and verification
  documentation.

### Task 1: Add the model capability catalog

**Files:**

- Create: `Talkie/Core/Engines/OpenAITranscriptionModel.swift`
- Modify: `Talkie/Data/ModelPresets.swift`
- Create: `TalkieTests/OpenAITranscriptionModelTests.swift`
- Modify: `TalkieTests/DictationProfileTests.swift`

- [ ] **Step 1: Write failing catalog tests**

```swift
import XCTest
@testable import Talkie

final class OpenAITranscriptionModelTests: XCTestCase {
    func testRecommendedModelsExposeDocumentedCapabilities() {
        XCTAssertEqual(OpenAITranscriptionModel.gptTranscribe.workflow, .batch)
        XCTAssertTrue(OpenAITranscriptionModel.gptTranscribe.supportsKeywords)
        XCTAssertTrue(OpenAITranscriptionModel.gptTranscribe.supportsMultipleLanguages)
        XCTAssertTrue(OpenAITranscriptionModel.gptTranscribe.returnsDetectedLanguages)
        XCTAssertEqual(OpenAITranscriptionModel.gptTranscribe.pricePerMinute, 0.0045)

        XCTAssertEqual(OpenAITranscriptionModel.gptLiveTranscribe.workflow, .realtime)
        XCTAssertTrue(OpenAITranscriptionModel.gptLiveTranscribe.supportsDelay)
        XCTAssertFalse(OpenAITranscriptionModel.gptLiveTranscribe.returnsDetectedLanguages)
        XCTAssertEqual(OpenAITranscriptionModel.gptLiveTranscribe.pricePerMinute, 0.017)
    }

    func testLegacyModelsRemainAvailableButAreNotDefaults() {
        XCTAssertEqual(ModelPresets.openAIBatch.first, "gpt-transcribe")
        XCTAssertEqual(ModelPresets.openAIRealtime.first, "gpt-live-transcribe")
        XCTAssertTrue(ModelPresets.openAIBatch.contains("gpt-4o-mini-transcribe"))
        XCTAssertTrue(ModelPresets.openAIBatch.contains("gpt-4o-transcribe"))
        XCTAssertTrue(ModelPresets.openAIRealtime.contains("gpt-realtime-whisper"))
        XCTAssertTrue(OpenAITranscriptionModel.gpt4oMiniTranscribe.isLegacy)
    }
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
xcodegen generate
xcodebuild test -project Talkie.xcodeproj -scheme Talkie -destination 'platform=macOS' \
  -only-testing:TalkieTests/OpenAITranscriptionModelTests CODE_SIGNING_ALLOWED=NO
```

Expected: compilation fails because `OpenAITranscriptionModel` and the separated
preset lists do not exist.

- [ ] **Step 3: Implement the capability catalog**

```swift
import Foundation

enum TranscriptionWorkflow: Equatable {
    case batch
    case realtime
    case committedTurn
}

enum OpenAITranscriptionModel: String, CaseIterable, Sendable {
    case gptTranscribe = "gpt-transcribe"
    case gptLiveTranscribe = "gpt-live-transcribe"
    case gpt4oTranscribe = "gpt-4o-transcribe"
    case gpt4oMiniTranscribe = "gpt-4o-mini-transcribe"
    case gptRealtimeWhisper = "gpt-realtime-whisper"

    var workflow: TranscriptionWorkflow {
        switch self {
        case .gptLiveTranscribe, .gptRealtimeWhisper: .realtime
        case .gptTranscribe: .batch
        case .gpt4oTranscribe, .gpt4oMiniTranscribe: .batch
        }
    }

    var supportsKeywords: Bool {
        self == .gptTranscribe || self == .gptLiveTranscribe
    }

    var supportsMultipleLanguages: Bool { supportsKeywords }
    var supportsDelay: Bool { self == .gptLiveTranscribe }
    var returnsDetectedLanguages: Bool { self == .gptTranscribe }

    var isLegacy: Bool {
        switch self {
        case .gptTranscribe, .gptLiveTranscribe: false
        default: true
        }
    }

    var pricePerMinute: Double {
        switch self {
        case .gptTranscribe: 0.0045
        case .gptLiveTranscribe, .gptRealtimeWhisper: 0.017
        case .gpt4oMiniTranscribe: 0.003
        case .gpt4oTranscribe: 0.006
        }
    }

    static func capabilities(for rawValue: String) -> OpenAITranscriptionModel? {
        OpenAITranscriptionModel(rawValue: rawValue)
    }
}
```

Update presets to:

```swift
static let openAIBatch = [
    "gpt-transcribe",
    "gpt-4o-mini-transcribe",
    "gpt-4o-transcribe",
]
static let openAIRealtime = [
    "gpt-live-transcribe",
    "gpt-transcribe",
    "gpt-realtime-whisper",
]
static let transcription = openAIBatch
```

Keep `transcription` as a compatibility alias until all profile tests and callers
move to `openAIBatch`.

- [ ] **Step 4: Run the catalog and profile tests**

Run:

```bash
xcodebuild test -project Talkie.xcodeproj -scheme Talkie -destination 'platform=macOS' \
  -only-testing:TalkieTests/OpenAITranscriptionModelTests \
  -only-testing:TalkieTests/DictationProfileTests CODE_SIGNING_ALLOWED=NO
```

Expected: both suites pass.

- [ ] **Step 5: Commit**

```bash
git add Talkie/Core/Engines/OpenAITranscriptionModel.swift \
  Talkie/Data/ModelPresets.swift TalkieTests/OpenAITranscriptionModelTests.swift \
  TalkieTests/DictationProfileTests.swift
git commit -m "feat: add OpenAI transcription model capabilities"
```

### Task 2: Build privacy-safe model context

**Files:**

- Create: `Talkie/Core/Engines/TranscriptionContext.swift`
- Modify: `Talkie/Data/SupportedLanguages.swift`
- Create: `TalkieTests/TranscriptionContextTests.swift`
- Create: `Talkie/Data/DictionaryKeywordValidator.swift`
- Modify: `Talkie/Data/HistoryStore.swift`
- Modify: `Talkie/UI/Hub/DictionaryView.swift`
- Modify: `TalkieTests/HistoryStoreTests.swift`
- Modify: `TalkieTests/SnippetProcessorTests.swift`

- [ ] **Step 1: Write failing context tests**

```swift
import XCTest
@testable import Talkie

final class TranscriptionContextTests: XCTestCase {
    func testNormalizesKeywordsAndLanguages() {
        let context = TranscriptionContext.build(
            prompt: "  A Talkie product demo.  ",
            dictionaryTerms: [" Talkie ", "talkie", "AC-42\r\nbilling", "<unsafe>"],
            languageCodes: ["en-US", "fr-CA", "zh-Hant", "bad value"])

        XCTAssertEqual(context.prompt, "A Talkie product demo.")
        XCTAssertEqual(context.keywords, ["Talkie", "AC-42 billing"])
        XCTAssertEqual(context.languages, ["en", "fr", "zh-tw"])
    }

    func testContextContainsOnlyExplicitConfiguration() {
        let context = TranscriptionContext.build(
            prompt: "",
            dictionaryTerms: [],
            languageCodes: [])
        XCTAssertNil(context.prompt)
        XCTAssertEqual(context.keywords, [])
        XCTAssertEqual(context.languages, [])
    }

func testNewAndLegacyModelsChooseDifferentLanguageFields() {
        let context = TranscriptionContext(
            prompt: "Product demo", keywords: ["Talkie"], languages: ["en", "de"])
        XCTAssertEqual(context.legacyLanguage, "en")
        XCTAssertEqual(context.languages, ["en", "de"])
    }
}

func testDictionaryKeywordValidatorRejectsServerForbiddenCharacters() {
    XCTAssertThrowsError(try DictionaryKeywordValidator.validate("bad<term"))
    XCTAssertThrowsError(try DictionaryKeywordValidator.validate("two\nlines"))
    XCTAssertNoThrow(try DictionaryKeywordValidator.validate("C++"))
}
```

- [ ] **Step 2: Run the tests and verify RED**

Run:

```bash
xcodebuild test -project Talkie.xcodeproj -scheme Talkie -destination 'platform=macOS' \
  -only-testing:TalkieTests/TranscriptionContextTests CODE_SIGNING_ALLOWED=NO
```

Expected: compilation fails because `TranscriptionContext` does not exist.

- [ ] **Step 3: Implement context normalization**

```swift
import Foundation

struct TranscriptionContext: Sendable, Equatable {
    let prompt: String?
    let keywords: [String]
    let languages: [String]

    var legacyLanguage: String? { languages.first }

    static func build(
        prompt: String,
        dictionaryTerms: [String],
        languageCodes: [String]
    ) -> Self {
        let normalizedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        var seenKeywords = Set<String>()
        let keywords = dictionaryTerms.compactMap { value -> String? in
            let singleLine = value
                .replacingOccurrences(of: "\r", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            guard !singleLine.isEmpty,
                  !singleLine.contains("<"),
                  !singleLine.contains(">") else { return nil }
            let key = singleLine.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current)
            guard seenKeywords.insert(key).inserted else { return nil }
            return singleLine
        }

        var seenLanguages = Set<String>()
        let languages = languageCodes.compactMap {
            SupportedLanguages.openAITranscriptionCode(for: $0)
        }.filter { seenLanguages.insert($0).inserted }

        return Self(
            prompt: normalizedPrompt.isEmpty ? nil : normalizedPrompt,
            keywords: keywords,
            languages: languages)
    }
}
```

Implement an explicit `openAITranscriptionCode(for:)` mapping. Map common regional
variants to their ISO 639-1 base, and map `zh-Hans`/`zh-Hant` to documented
`zh-cn`/`zh-tw`. Return `nil` for values not present in the supported picker.

- [ ] **Step 4: Reject new server-invalid dictionary hints**

Create the validator:

```swift
enum DictionaryKeywordValidationError: LocalizedError, Equatable {
    case forbiddenCharacter

    var errorDescription: String? {
        "Keywords cannot contain <, >, or line breaks."
    }
}

enum DictionaryKeywordValidator {
    static func validate(_ value: String) throws {
        guard !value.contains("<"), !value.contains(">"),
              !value.contains("\r"), !value.contains("\n") else {
            throw DictionaryKeywordValidationError.forbiddenCharacter
        }
    }
}
```

Call it from `HistoryStore.addTerm` and `updateTerm` before persistence, change
those methods to `throws`, and catch
`DictionaryKeywordValidationError.forbiddenCharacter` in `DictionaryView`.
Display its localized error underneath the editor in red. Update current callers
in `TalkieTests/HistoryStoreTests.swift` and
`TalkieTests/SnippetProcessorTests.swift` to use `try`/`try?` explicitly.

- [ ] **Step 5: Run context and dictionary tests**

Run:

```bash
xcodebuild test -project Talkie.xcodeproj -scheme Talkie -destination 'platform=macOS' \
  -only-testing:TalkieTests/TranscriptionContextTests \
  -only-testing:TalkieTests/HistoryStoreTests \
  -only-testing:TalkieTests/SnippetProcessorTests CODE_SIGNING_ALLOWED=NO
```

Expected: all selected tests pass.

- [ ] **Step 6: Commit**

```bash
git add Talkie/Core/Engines/TranscriptionContext.swift \
  Talkie/Data/SupportedLanguages.swift Talkie/Data/DictionaryKeywordValidator.swift \
  Talkie/Data/HistoryStore.swift Talkie/UI/Hub/DictionaryView.swift \
  TalkieTests/TranscriptionContextTests.swift TalkieTests/HistoryStoreTests.swift \
  TalkieTests/SnippetProcessorTests.swift
git commit -m "feat: build safe transcription context"
```

### Task 3: Add settings defaults and non-destructive migration

**Files:**

- Modify: `Talkie/Data/SettingsStore.swift`
- Modify: `TalkieTests/SettingsStoreTests.swift`
- Modify: `Talkie/Data/DictationProfile.swift`
- Modify: `TalkieTests/DictationProfileTests.swift`
- Modify: `Talkie/App/AppEnvironment.swift`
- Modify: `TalkieTests/AppEnvironmentTests.swift`

- [ ] **Step 1: Write failing default and migration tests**

```swift
func testNewTranscriptionDefaults() {
    let defaults = UserDefaults(suiteName: "talkie-tests-\(UUID().uuidString)")!
    let store = SettingsStore(defaults: defaults)
    XCTAssertEqual(store.transcriptionModel, "gpt-transcribe")
    XCTAssertEqual(store.realtimeTranscriptionModel, "gpt-live-transcribe")
    XCTAssertEqual(store.realtimeTranscriptionDelay, .medium)
    XCTAssertEqual(store.transcriptionContextPrompt, "")
    XCTAssertEqual(store.expectedInputLanguages, [])
    XCTAssertTrue(store.streamBatchTranscription)
}

func testExistingModelSelectionIsPreserved() {
    let defaults = UserDefaults(suiteName: "talkie-tests-\(UUID().uuidString)")!
    defaults.set("gpt-4o-mini-transcribe", forKey: "transcriptionModel")
    XCTAssertEqual(
        SettingsStore(defaults: defaults).transcriptionModel,
        "gpt-4o-mini-transcribe")
}

func testExpectedLanguagesMigrateOnceFromPinnedLanguage() {
    let defaults = UserDefaults(suiteName: "talkie-tests-\(UUID().uuidString)")!
    defaults.set("de", forKey: "pinnedLanguage")
    let store = SettingsStore(defaults: defaults)
    XCTAssertEqual(store.expectedInputLanguages, ["de"])
    XCTAssertEqual(defaults.stringArray(forKey: "expectedInputLanguages"), ["de"])
}
```

- [ ] **Step 2: Run Settings tests and verify RED**

Run:

```bash
xcodebuild test -project Talkie.xcodeproj -scheme Talkie -destination 'platform=macOS' \
  -only-testing:TalkieTests/SettingsStoreTests CODE_SIGNING_ALLOWED=NO
```

Expected: missing-property compilation failures.

- [ ] **Step 3: Add the delay type and persisted fields**

Put the delay enum beside the model catalog:

```swift
enum RealtimeTranscriptionDelay: String, CaseIterable, Sendable {
    case minimal, low, medium, high, xhigh

    var title: String {
        switch self {
        case .minimal: "Fastest"
        case .low: "Fast"
        case .medium: "Balanced"
        case .high: "Accurate"
        case .xhigh: "Most accurate"
        }
    }
}
```

Add `SettingsStore` properties with the same persistence pattern as existing fields:

```swift
var realtimeTranscriptionModel: String {
    didSet { defaults.set(realtimeTranscriptionModel, forKey: "realtimeTranscriptionModel") }
}
var realtimeTranscriptionDelay: RealtimeTranscriptionDelay {
    didSet { defaults.set(realtimeTranscriptionDelay.rawValue, forKey: "realtimeTranscriptionDelay") }
}
var transcriptionContextPrompt: String {
    didSet { defaults.set(transcriptionContextPrompt, forKey: "transcriptionContextPrompt") }
}
var expectedInputLanguages: [String] {
    didSet { defaults.set(expectedInputLanguages, forKey: "expectedInputLanguages") }
}
var streamBatchTranscription: Bool {
    didSet { defaults.set(streamBatchTranscription, forKey: "streamBatchTranscription") }
}
```

Initialize fresh defaults to the approved values. Detect migration with
`defaults.object(forKey: "expectedInputLanguages") == nil`; seed only then and
persist the result so a user can later intentionally clear the array.

- [ ] **Step 4: Update built-in profiles and E2E defaults**

Use `gpt-transcribe` for built-in OpenAI batch fields. Do not add the Realtime model
to `DictationProfile`; it is a global Instant transport setting, matching the
existing design in which every Instant profile requires OpenAI.

Set deterministic E2E defaults:

```swift
defaults.set("gpt-transcribe", forKey: "transcriptionModel")
defaults.set("gpt-live-transcribe", forKey: "realtimeTranscriptionModel")
defaults.set("medium", forKey: "realtimeTranscriptionDelay")
defaults.set(["en"], forKey: "expectedInputLanguages")
defaults.set(false, forKey: "streamBatchTranscription")
```

E2E disables batch SSE so existing fixture scenarios remain deterministic until a
dedicated SSE fixture is selected.

- [ ] **Step 5: Run settings, profile, and environment tests**

Run:

```bash
xcodebuild test -project Talkie.xcodeproj -scheme Talkie -destination 'platform=macOS' \
  -only-testing:TalkieTests/SettingsStoreTests \
  -only-testing:TalkieTests/DictationProfileTests \
  -only-testing:TalkieTests/AppEnvironmentTests CODE_SIGNING_ALLOWED=NO
```

Expected: all selected suites pass.

- [ ] **Step 6: Commit**

```bash
git add Talkie/Data/SettingsStore.swift Talkie/Data/DictationProfile.swift \
  Talkie/App/AppEnvironment.swift TalkieTests/SettingsStoreTests.swift \
  TalkieTests/DictationProfileTests.swift TalkieTests/AppEnvironmentTests.swift
git commit -m "feat: default Talkie to new transcription models"
```

### Task 4: Integrate `gpt-transcribe` batch requests and detected languages

**Files:**

- Modify: `Talkie/Core/Engines/TranscriptionEngine.swift`
- Modify: `Talkie/Core/Engines/OpenAIEngine.swift`
- Modify: `TalkieTests/OpenAIEngineTests.swift`
- Modify: `TalkieTests/EngineRouterTests.swift`

- [ ] **Step 1: Write failing multipart and response tests**

Add tests that capture the multipart body and assert:

```swift
XCTAssertTrue(body.contains("name=\"model\""))
XCTAssertTrue(body.contains("\r\n\r\ngpt-transcribe\r\n"))
XCTAssertTrue(body.contains("name=\"prompt\""))
XCTAssertTrue(body.contains("name=\"keywords[]\""))
XCTAssertTrue(body.contains("\r\n\r\nTalkie\r\n"))
XCTAssertTrue(body.contains("name=\"languages[]\""))
XCTAssertTrue(body.contains("\r\n\r\nen\r\n"))
XCTAssertTrue(body.contains("\r\n\r\nde\r\n"))
XCTAssertFalse(body.contains("name=\"language\""))
```

Stub:

```json
{"text":"Hallo Talkie","languages":[{"code":"de"}]}
```

Assert:

```swift
XCTAssertEqual(result.engineID, "gpt-transcribe")
XCTAssertEqual(result.detectedLanguages, ["de"])
```

Add a legacy test asserting `gpt-4o-mini-transcribe` receives `prompt` and singular
`language`, but no `keywords[]` or `languages[]`.

- [ ] **Step 2: Run `OpenAIEngineTests` and verify RED**

Run:

```bash
xcodebuild test -project Talkie.xcodeproj -scheme Talkie -destination 'platform=macOS' \
  -only-testing:TalkieTests/OpenAIEngineTests CODE_SIGNING_ALLOWED=NO
```

Expected: new-model field and metadata assertions fail.

- [ ] **Step 3: Extend `Transcript` and `OpenAIEngine`**

Extend the value without changing existing call sites:

```swift
struct Transcript: Sendable, Equatable {
    let text: String
    var engineID: String = "openai"
    var usedFallback: Bool = false
    var detectedLanguages: [String] = []
}
```

Replace separate vocabulary/language providers on `OpenAIEngine` with a context
provider:

```swift
var contextProvider: @Sendable ([String]) -> TranscriptionContext
var streamProvider: @Sendable () -> Bool = { false }
```

For new-model multipart fields:

```swift
if let prompt = context.prompt { field("prompt", prompt) }
for keyword in context.keywords { field("keywords[]", keyword) }
for language in context.languages { field("languages[]", language) }
```

For legacy models, keep:

```swift
if !context.keywords.isEmpty {
    field("prompt", "Vocabulary: " + context.keywords.joined(separator: ", "))
}
if let language = context.legacyLanguage { field("language", language) }
```

Decode detected languages:

```swift
struct Response: Decodable {
    struct Language: Decodable { let code: String }
    let text: String
    let languages: [Language]?
}
return Transcript(
    text: decoded.text,
    engineID: model,
    detectedLanguages: decoded.languages?.map(\.code) ?? [])
```

- [ ] **Step 4: Preserve OpenRouter and local behavior**

Update test fakes and protocol users only for the additive
`detectedLanguages` field. Do not add OpenAI-only fields to
`OpenRouterTranscriptionEngine` or `ParakeetEngine`.

- [ ] **Step 5: Run engine suites**

Run:

```bash
xcodebuild test -project Talkie.xcodeproj -scheme Talkie -destination 'platform=macOS' \
  -only-testing:TalkieTests/OpenAIEngineTests \
  -only-testing:TalkieTests/OpenRouterTranscriptionEngineTests \
  -only-testing:TalkieTests/ParakeetEngineTests \
  -only-testing:TalkieTests/EngineRouterTests CODE_SIGNING_ALLOWED=NO
```

Expected: all selected suites pass.

- [ ] **Step 6: Commit**

```bash
git add Talkie/Core/Engines/TranscriptionEngine.swift \
  Talkie/Core/Engines/OpenAIEngine.swift TalkieTests/OpenAIEngineTests.swift \
  TalkieTests/EngineRouterTests.swift TalkieTests/OpenRouterTranscriptionEngineTests.swift \
  TalkieTests/ParakeetEngineTests.swift
git commit -m "feat: integrate gpt-transcribe batch context"
```

### Task 5: Add completed-file SSE streaming

**Files:**

- Create: `Talkie/Core/Engines/OpenAISSEParser.swift`
- Create: `TalkieTests/OpenAISSEParserTests.swift`
- Modify: `Talkie/Core/Engines/TranscriptionEngine.swift`
- Modify: `Talkie/Core/Engines/OpenAIEngine.swift`
- Modify: `Talkie/Core/Engines/EngineRouter.swift`
- Modify: `Talkie/Core/Engines/OpenRouterTranscriptionEngine.swift`
- Modify: `Talkie/Core/Engines/ParakeetEngine.swift`
- Modify: `TalkieTests/OpenAIEngineTests.swift`
- Modify: `TalkieTests/EngineRouterTests.swift`
- Modify: `TalkieTests/OpenRouterTranscriptionEngineTests.swift`
- Modify: `TalkieTests/ParakeetEngineTests.swift`
- Modify: `TalkieTests/DictationCoordinatorTests.swift`

- [ ] **Step 1: Write fragmented SSE parser tests**

```swift
func testParsesFragmentedDeltaAndDoneEvents() throws {
    var parser = OpenAISSEParser()
    XCTAssertEqual(try parser.append(Data("data: {\"type\":\"transcript.text.del".utf8)), [])
    let events = try parser.append(Data(
        "ta\",\"delta\":\"Hel\"}\n\ndata: {\"type\":\"transcript.text.done\",\"text\":\"Hello\",\"languages\":[{\"code\":\"en\"}]}\n\n".utf8))
    XCTAssertEqual(events, [
        .delta("Hel"),
        .done(text: "Hello", detectedLanguages: ["en"]),
    ])
}

func testRejectsDoneEventWithoutText() {
    var parser = OpenAISSEParser()
    XCTAssertThrowsError(try parser.append(
        Data("data: {\"type\":\"transcript.text.done\"}\n\n".utf8)))
}
```

- [ ] **Step 2: Run parser tests and verify RED**

Run:

```bash
xcodebuild test -project Talkie.xcodeproj -scheme Talkie -destination 'platform=macOS' \
  -only-testing:TalkieTests/OpenAISSEParserTests CODE_SIGNING_ALLOWED=NO
```

Expected: missing-type compilation failure.

- [ ] **Step 3: Implement an incremental SSE parser**

```swift
enum OpenAISSEEvent: Equatable {
    case delta(String)
    case done(text: String, detectedLanguages: [String])
}

struct OpenAISSEParser {
    private var buffer = Data()

    mutating func append(_ data: Data) throws -> [OpenAISSEEvent] {
        buffer.append(data)
        var events: [OpenAISSEEvent] = []
        let delimiter = Data("\n\n".utf8)
        while let range = buffer.range(of: delimiter) {
            let frame = buffer[..<range.lowerBound]
            buffer.removeSubrange(..<range.upperBound)
            guard let line = String(data: frame, encoding: .utf8)?
                .split(separator: "\n")
                .first(where: { $0.hasPrefix("data: ") }) else { continue }
            let json = Data(line.dropFirst(6).utf8)
            let object = try JSONSerialization.jsonObject(with: json) as? [String: Any]
            switch object?["type"] as? String {
            case "transcript.text.delta":
                events.append(.delta(object?["delta"] as? String ?? ""))
            case "transcript.text.done":
                guard let text = object?["text"] as? String else {
                    throw EngineError.invalidResponse
                }
                let languages = (object?["languages"] as? [[String: Any]])?
                    .compactMap { $0["code"] as? String } ?? []
                events.append(.done(text: text, detectedLanguages: languages))
            default:
                continue
            }
        }
        return events
    }
}
```

- [ ] **Step 4: Add a progress-capable engine entry point**

Define:

```swift
typealias TranscriptionProgressSink = @Sendable (String) -> Void

protocol TranscriptionEngine: Sendable {
    func transcribe(
        _ audio: RecordedAudio,
        dictionaryTerms: [String],
        onPartial: TranscriptionProgressSink?
    ) async throws -> Transcript
}

extension TranscriptionEngine {
    func transcribe(
        _ audio: RecordedAudio,
        dictionaryTerms: [String]
    ) async throws -> Transcript {
        try await transcribe(audio, dictionaryTerms: dictionaryTerms, onPartial: nil)
    }
}
```

Update `OpenRouterTranscriptionEngine`, `ParakeetEngine`, and the fake engines in
`EngineRouterTests` and `DictationCoordinatorTests` to accept and ignore
`onPartial`.

- [ ] **Step 5: Implement streamed file handling**

Only when model is `gpt-transcribe` and `streamProvider()` is true:

```swift
field("stream", "true")
let (bytes, response) = try await session.bytes(for: request)
try validate(response)
var parser = OpenAISSEParser()
var final: Transcript?
for try await byte in bytes {
    for event in try parser.append(Data([byte])) {
        switch event {
        case .delta(let delta):
            accumulated += delta
            onPartial?(accumulated)
        case .done(let text, let languages):
            final = Transcript(
                text: text,
                engineID: model,
                detectedLanguages: languages)
        }
    }
}
guard let final else { throw EngineError.invalidResponse }
return final
```

Exercise `OpenAIEngine` with `StubURLProtocol` returning the complete SSE body.
Fragmentation behavior is owned by `OpenAISSEParserTests`. Do not return
`accumulated` if the final event is missing.

- [ ] **Step 6: Run all engine tests**

Run:

```bash
xcodebuild test -project Talkie.xcodeproj -scheme Talkie -destination 'platform=macOS' \
  -only-testing:TalkieTests/OpenAISSEParserTests \
  -only-testing:TalkieTests/OpenAIEngineTests \
  -only-testing:TalkieTests/EngineRouterTests \
  -only-testing:TalkieTests/OpenRouterTranscriptionEngineTests \
  -only-testing:TalkieTests/ParakeetEngineTests \
  -only-testing:TalkieTests/DictationCoordinatorTests CODE_SIGNING_ALLOWED=NO
```

Expected: all selected suites pass, including a missing-final-event failure test.

- [ ] **Step 7: Commit**

```bash
git add Talkie/Core/Engines TalkieTests/OpenAISSEParserTests.swift \
  TalkieTests/OpenAIEngineTests.swift TalkieTests/EngineRouterTests.swift \
  TalkieTests/OpenRouterTranscriptionEngineTests.swift \
  TalkieTests/ParakeetEngineTests.swift TalkieTests/DictationCoordinatorTests.swift
git commit -m "feat: stream completed-file transcription progress"
```

### Task 6: Integrate `gpt-live-transcribe` and latency controls

**Files:**

- Modify: `Talkie/Core/Engines/Realtime/RealtimeEvents.swift`
- Modify: `Talkie/Core/Engines/Realtime/OpenAIRealtimeSession.swift`
- Modify: `TalkieTests/RealtimeEventsTests.swift`
- Modify: `TalkieTests/OpenAIRealtimeSessionTests.swift`

- [ ] **Step 1: Write failing Realtime session JSON tests**

Decode JSON to dictionaries rather than matching unordered JSON text:

```swift
let event = RealtimeClientEvent.sessionUpdate(
    model: "gpt-live-transcribe",
    context: TranscriptionContext(
        prompt: "Talkie demo",
        keywords: ["Talkie", "AC-42"],
        languages: ["en", "de"]),
    delay: .low)
let root = try XCTUnwrap(
    JSONSerialization.jsonObject(with: event.encoded()) as? [String: Any])
let session = try XCTUnwrap(root["session"] as? [String: Any])
let audio = try XCTUnwrap(session["audio"] as? [String: Any])
let input = try XCTUnwrap(audio["input"] as? [String: Any])
let transcription = try XCTUnwrap(input["transcription"] as? [String: Any])
XCTAssertEqual(transcription["model"] as? String, "gpt-live-transcribe")
XCTAssertEqual(transcription["keywords"] as? [String], ["Talkie", "AC-42"])
XCTAssertEqual(transcription["languages"] as? [String], ["en", "de"])
XCTAssertEqual(transcription["delay"] as? String, "low")
XCTAssertNil(transcription["language"])
```

Add a legacy test asserting `gpt-realtime-whisper` keeps `prompt` plus singular
`language` and does not receive `keywords`, plural `languages`, or `delay`.

- [ ] **Step 2: Run Realtime tests and verify RED**

Run:

```bash
xcodebuild test -project Talkie.xcodeproj -scheme Talkie -destination 'platform=macOS' \
  -only-testing:TalkieTests/RealtimeEventsTests CODE_SIGNING_ALLOWED=NO
```

Expected: signature and field assertions fail.

- [ ] **Step 3: Make session encoding capability-aware**

Change the event case:

```swift
case sessionUpdate(
    model: String,
    context: TranscriptionContext,
    delay: RealtimeTranscriptionDelay
)
```

For `gpt-live-transcribe`, encode `prompt`, `keywords`, `languages`, and `delay`.
For `gpt-transcribe` committed-turn mode, encode prompt/keywords/languages without
delay. For `gpt-realtime-whisper`, preserve current prompt/singular-language fields.
Keep the existing 24 kHz PCM and `server_vad` configuration.

- [ ] **Step 4: Update the live session**

Use:

```swift
private let context: TranscriptionContext
private let delay: RealtimeTranscriptionDelay
```

Send the new session update in `begin()`. Return:

```swift
return Transcript(
    text: text,
    engineID: model,
    detectedLanguages: detectedLanguageCodes)
```

Keep all existing item-ID keyed state, duplicate-event handling, final-commit
correlation, settling interval, hard timeout, and cancellation cleanup unchanged.

- [ ] **Step 5: Decode optional committed-turn languages**

Change completion to:

```swift
case transcriptCompleted(
    itemID: String,
    transcript: String,
    detectedLanguages: [String]
)
```

Decode `languages[].code` when present. Aggregate unique codes in commit order.
For `gpt-live-transcribe`, the array normally stays empty.

- [ ] **Step 6: Run the full Realtime suites**

Run:

```bash
xcodebuild test -project Talkie.xcodeproj -scheme Talkie -destination 'platform=macOS' \
  -only-testing:TalkieTests/RealtimeEventsTests \
  -only-testing:TalkieTests/OpenAIRealtimeSessionTests CODE_SIGNING_ALLOWED=NO
```

Expected: all existing race/finalization tests and new context/delay tests pass.

- [ ] **Step 7: Commit**

```bash
git add Talkie/Core/Engines/Realtime/RealtimeEvents.swift \
  Talkie/Core/Engines/Realtime/OpenAIRealtimeSession.swift \
  TalkieTests/RealtimeEventsTests.swift TalkieTests/OpenAIRealtimeSessionTests.swift
git commit -m "feat: integrate gpt-live-transcribe sessions"
```

### Task 7: Wire models, context, progress, and accurate pricing into the app

**Files:**

- Modify: `Talkie/App/AppDelegate.swift`
- Modify: `Talkie/Core/DictationCoordinator.swift`
- Modify: `Talkie/Core/PriceBook.swift`
- Modify: `TalkieTests/DictationCoordinatorTests.swift`
- Modify: `TalkieTests/PriceBookTests.swift`

- [ ] **Step 1: Write failing wiring-facing tests**

Add price assertions:

```swift
XCTAssertEqual(
    PriceBook.estimate(
        engine: "gpt-transcribe", durationSec: 60,
        cleanupModel: nil, wordCount: 0),
    0.0045,
    accuracy: 0.000_001)
XCTAssertEqual(
    PriceBook.estimate(
        engine: "gpt-live-transcribe", durationSec: 60,
        cleanupModel: nil, wordCount: 0),
    0.017,
    accuracy: 0.000_001)
```

Add a coordinator test whose fake engine calls:

```swift
onPartial?("partial batch text")
```

Assert the partial preview is exposed through the existing pill partial-state
mechanism, but final insertion/history uses only the final `Transcript.text`.

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
xcodebuild test -project Talkie.xcodeproj -scheme Talkie -destination 'platform=macOS' \
  -only-testing:TalkieTests/PriceBookTests \
  -only-testing:TalkieTests/DictationCoordinatorTests CODE_SIGNING_ALLOWED=NO
```

Expected: new price or progress assertions fail.

- [ ] **Step 3: Construct one context per dictation**

In `AppDelegate`, replace the hardcoded live model and old language provider with:

```swift
let context = TranscriptionContext.build(
    prompt: defaults.string(forKey: "transcriptionContextPrompt") ?? "",
    dictionaryTerms: history?.dictionaryPromptTerms() ?? [],
    languageCodes: defaults.stringArray(forKey: "expectedInputLanguages") ?? [])
let model = defaults.string(forKey: "realtimeTranscriptionModel")
    ?? "gpt-live-transcribe"
let delay = RealtimeTranscriptionDelay(
    rawValue: defaults.string(forKey: "realtimeTranscriptionDelay") ?? "")
    ?? .medium
```

Pass these values to `OpenAIRealtimeSession`. Build the same context in
`OpenAIEngine` from its explicit providers.

- [ ] **Step 4: Route batch partials to the pill only**

Pass an `onPartial` sink only for cloud batch mode. Store the latest value in the
same thread-safe partial box used by Realtime preview. Do not call
`LiveTextInserter` for batch partials. Clear the preview on completion, failure, or
cancel.

- [ ] **Step 5: Update pricing and engine IDs**

Add:

```swift
"gpt-transcribe": 0.0045,
"gpt-live-transcribe": 0.017,
"gpt-realtime-whisper": 0.017,
```

Retain old prices for old history. Replace generic new records such as `"openai"`
and `"realtime"` with the actual model ID returned by the engine. Keep generic
fallback rates for existing records.

- [ ] **Step 6: Run coordinator and pricing suites**

Run:

```bash
xcodebuild test -project Talkie.xcodeproj -scheme Talkie -destination 'platform=macOS' \
  -only-testing:TalkieTests/PriceBookTests \
  -only-testing:TalkieTests/DictationCoordinatorTests \
  -only-testing:TalkieTests/AppEnvironmentTests CODE_SIGNING_ALLOWED=NO
```

Expected: all selected suites pass.

- [ ] **Step 7: Commit**

```bash
git add Talkie/App/AppDelegate.swift Talkie/Core/DictationCoordinator.swift \
  Talkie/Core/PriceBook.swift TalkieTests/DictationCoordinatorTests.swift \
  TalkieTests/PriceBookTests.swift TalkieTests/AppEnvironmentTests.swift
git commit -m "feat: wire new transcription models into dictation"
```

### Task 8: Persist and display detected languages

**Files:**

- Modify: `Talkie/Data/DictationRecord.swift`
- Modify: `Talkie/Data/HistoryStore.swift`
- Modify: `Talkie/Core/DictationCoordinator.swift`
- Modify: `TalkieTests/HistoryStoreTests.swift`
- Modify: `TalkieTests/DictationCoordinatorTests.swift`
- Modify: `Talkie/UI/Hub/HistoryView.swift`

- [ ] **Step 1: Write failing persistence tests**

```swift
func testDetectedLanguagesRoundTripSeparatelyFromOutputLanguage() throws {
    let record = DictationRecord(
        rawText: "Bonjour", cleanedText: "Bonjour",
        appBundleID: nil, appName: nil, durationSec: 1,
        engine: "gpt-transcribe", status: .completed,
        language: "English",
        detectedLanguages: ["fr"])
    XCTAssertEqual(record.language, "English")
    XCTAssertEqual(record.detectedLanguages, ["fr"])
}
```

Add a coordinator assertion that a `Transcript` with `["de", "en"]` sends those
codes to `HistoryStore.save`.

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
xcodebuild test -project Talkie.xcodeproj -scheme Talkie -destination 'platform=macOS' \
  -only-testing:TalkieTests/HistoryStoreTests \
  -only-testing:TalkieTests/DictationCoordinatorTests CODE_SIGNING_ALLOWED=NO
```

Expected: initializer/signature compilation failures.

- [ ] **Step 3: Add optional SwiftData storage**

Use a JSON-backed optional property so migration is additive:

```swift
var detectedLanguagesJSON: String?

var detectedLanguages: [String] {
    get {
        guard let data = detectedLanguagesJSON?.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
    set {
        detectedLanguagesJSON = (try? JSONEncoder().encode(newValue))
            .map { String(decoding: $0, as: UTF8.self) }
    }
}
```

Initialize it from a new `detectedLanguages: [String] = []` parameter. Do not
repurpose the existing configured `language` column.

- [ ] **Step 4: Save and show detected languages**

Pass `transcript.detectedLanguages` through `HistoryStore.save`. In History, show a
secondary badge only when non-empty:

```swift
if !record.detectedLanguages.isEmpty {
    Label(
        "Detected: \(record.detectedLanguages.joined(separator: ", "))",
        systemImage: "character.bubble")
        .font(.caption)
        .foregroundStyle(.secondary)
}
```

Use localized language names when `Locale` can resolve them; fall back to the code.

- [ ] **Step 5: Run history and coordinator tests**

Run:

```bash
xcodebuild test -project Talkie.xcodeproj -scheme Talkie -destination 'platform=macOS' \
  -only-testing:TalkieTests/HistoryStoreTests \
  -only-testing:TalkieTests/DictationCoordinatorTests CODE_SIGNING_ALLOWED=NO
```

Expected: all selected suites pass.

- [ ] **Step 6: Commit**

```bash
git add Talkie/Data/DictationRecord.swift Talkie/Data/HistoryStore.swift \
  Talkie/Core/DictationCoordinator.swift Talkie/UI \
  TalkieTests/HistoryStoreTests.swift TalkieTests/DictationCoordinatorTests.swift
git commit -m "feat: retain detected transcription languages"
```

### Task 9: Expose the new functionality in native Settings

**Files:**

- Modify: `Talkie/UI/Hub/SettingsView.swift`
- Modify: `Talkie/UI/Hub/SimpleSettingsView.swift`
- Create: `TalkieUITests/SettingsUITests.swift`

- [ ] **Step 1: Add failing deterministic UI assertions**

Launch with isolated E2E defaults and assert the Advanced Engines pane exposes:

```swift
XCTAssertTrue(app.popUpButtons["Batch transcription model"].exists)
XCTAssertTrue(app.popUpButtons["Instant transcription model"].exists)
XCTAssertTrue(app.popUpButtons["Instant latency"].exists)
XCTAssertTrue(app.buttons["Expected speech languages"].exists)
XCTAssertTrue(app.textFields["Recording context"].exists)
XCTAssertTrue(app.checkBoxes["Show batch transcription progress"].exists)
```

Select the Legacy batch model and assert the Legacy help label appears. Select
`gpt-live-transcribe` and each latency value, relaunch, and assert persistence.

- [ ] **Step 2: Run the focused UI test and verify RED**

Run:

```bash
xcodebuild test -project Talkie.xcodeproj -scheme Talkie \
  -destination 'platform=macOS' -only-testing:TalkieUITests/SettingsUITests
```

Expected: the new controls are not found.

- [ ] **Step 3: Separate batch and instant model controls**

Render preset rows using capability metadata:

```swift
Picker("Batch transcription model", selection: $settings.transcriptionModel) {
    ForEach(ModelPresets.openAIBatch, id: \.self) { model in
        let suffix = OpenAITranscriptionModel(rawValue: model)?.isLegacy == true
            ? " — Legacy"
            : " — Recommended"
        Text(model + suffix).tag(model)
    }
}

Picker("Instant transcription model", selection: $settings.realtimeTranscriptionModel) {
    ForEach(ModelPresets.openAIRealtime, id: \.self) { model in
        Text(modelDisplayName(model)).tag(model)
    }
}
```

Label `gpt-transcribe` in the Instant picker as
`Committed turns — accurate, no continuous live deltas`.

- [ ] **Step 4: Add latency, context, language, and progress controls**

```swift
Picker("Instant latency", selection: $settings.realtimeTranscriptionDelay) {
    ForEach(RealtimeTranscriptionDelay.allCases, id: \.self) {
        Text($0.title).tag($0)
    }
}

TextField("Recording context", text: $settings.transcriptionContextPrompt)

Toggle(
    "Show batch transcription progress",
    isOn: $settings.streamBatchTranscription)
```

Implement expected speech languages as a menu of toggles. `Auto-detect` clears the
array; selecting a language adds/removes its provider code without affecting
`pinnedLanguage`. Explain that recording context, dictionary keywords, and selected
language hints go to the transcription provider, but surrounding text never does.

- [ ] **Step 5: Update Simple Settings**

Keep the profile picker primary. Add compact read-only text:

```swift
Text(settings.engineMode == "instant"
     ? "Live model: \(settings.realtimeTranscriptionModel)"
     : "Batch model: \(settings.transcriptionModel)")
    .font(.caption)
    .foregroundStyle(.secondary)
```

Rename ambiguous language copy so `pinnedLanguage` is clearly the output/cleanup
language, not the new multi-language ASR hint.

- [ ] **Step 6: Run UI and Settings logic tests**

Run:

```bash
xcodebuild test -project Talkie.xcodeproj -scheme Talkie \
  -destination 'platform=macOS' -only-testing:TalkieUITests/SettingsUITests
xcodebuild test -project Talkie.xcodeproj -scheme Talkie \
  -destination 'platform=macOS' -only-testing:TalkieTests/SettingsStoreTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: UI and logic tests pass.

- [ ] **Step 7: Commit**

```bash
git add Talkie/UI/Hub/SettingsView.swift Talkie/UI/Hub/SimpleSettingsView.swift \
  TalkieUITests TalkieTests/SettingsStoreTests.swift
git commit -m "feat: expose transcription model controls"
```

### Task 10: Update opt-in live verification

**Files:**

- Modify: `scripts/live-verify.sh`
- Modify: `scripts/test-release-pipeline.sh`
- Modify: `CONTRIBUTING.md`

- [ ] **Step 1: Add failing static script assertions**

In `scripts/test-release-pipeline.sh`, assert the live script contains:

```bash
expect_pattern scripts/live-verify.sh 'model=gpt-transcribe' \
  "live verification must exercise gpt-transcribe"
expect_pattern scripts/live-verify.sh 'stream=true' \
  "live verification must exercise completed-file streaming"
expect_pattern scripts/live-verify.sh 'gpt-live-transcribe' \
  "live verification must exercise gpt-live-transcribe"
```

- [ ] **Step 2: Run the release-pipeline test and verify RED**

Run:

```bash
bash scripts/test-release-pipeline.sh
```

Expected: missing new-model patterns are reported.

- [ ] **Step 3: Update the file transcription smoke checks**

Send the same non-sensitive fixture twice:

```bash
curl --fail --silent --show-error https://api.openai.com/v1/audio/transcriptions \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -F model=gpt-transcribe \
  -F response_format=json \
  -F "keywords[]=Talkie" \
  -F "languages[]=en" \
  -F "file=@$TALKIE_LIVE_AUDIO;type=audio/mp4"
```

The second request adds `-F stream=true` and verifies at least one
`transcript.text.done` event with non-empty text. Never print the returned transcript.

- [ ] **Step 4: Add a bounded Realtime smoke client**

Add a small Swift script under `scripts/support/verify-live-transcription.swift`
that:

1. opens `wss://api.openai.com/v1/realtime?intent=transcription`;
2. sends a `session.update` for `gpt-live-transcribe`, `languages: ["en"]`, and
   `delay: "medium"`;
3. converts the fixture to 24 kHz PCM using `AVFoundation`;
4. appends chunks and commits;
5. waits at most 20 seconds for a non-empty completed event;
6. prints only `Realtime live transcription verification passed.`

Do not print transcript text or the API key. The shell script invokes this helper
only in the opt-in live command.

- [ ] **Step 5: Run deterministic script tests**

Run:

```bash
bash scripts/test-release-pipeline.sh
bash scripts/test-public-readiness.sh
```

Expected: both pass without credentials or network calls.

- [ ] **Step 6: Run live verification only when credentials are intentionally available**

Run:

```bash
OPENAI_API_KEY=... OPENROUTER_API_KEY=... \
TALKIE_LIVE_AUDIO=/absolute/path/to/non-sensitive-fixture.m4a \
scripts/live-verify.sh
```

Expected:

```text
Live provider verification passed (OpenAI + OpenRouter).
Realtime live transcription verification passed.
```

If credentials are unavailable, record this step as not run; do not weaken or fake
the check.

- [ ] **Step 7: Commit**

```bash
git add scripts/live-verify.sh scripts/support/verify-live-transcription.swift \
  scripts/test-release-pipeline.sh CONTRIBUTING.md
git commit -m "test: verify new OpenAI transcription models"
```

### Task 11: Update public documentation and release matrix

**Files:**

- Modify: `README.md`
- Modify: `docs/testing-matrix.md`
- Modify: `CONTRIBUTING.md`
- Modify: `scripts/verify-docs.sh`

- [ ] **Step 1: Add documentation checks before changing prose**

Extend the existing documentation/static verification script to require:

```text
gpt-transcribe
gpt-live-transcribe
$0.0045/min
$0.017/min
expected speech languages
recording context
```

The checks should inspect README and the testing matrix, not UI source files.

- [ ] **Step 2: Run documentation verification and verify RED**

Run:

```bash
bash scripts/verify-docs.sh
```

Expected: new model/capability documentation checks fail.

- [ ] **Step 3: Document behavior and privacy accurately**

Update README provider behavior:

- Batch OpenAI defaults to `gpt-transcribe`.
- Instant defaults to `gpt-live-transcribe`.
- OpenAI receives audio plus explicit prompt/keywords/language hints.
- Surrounding focused-field context is never sent to transcription.
- OpenRouter/local alternatives remain available.
- Prices are estimates and may change.

Add manual release checks for:

```text
- Fresh install receives the new defaults.
- Existing legacy model selection survives upgrade.
- Dictionary keyword improves a domain-term fixture without hallucinating it in silence.
- English/German code-switching works with both expected languages selected.
- Each live delay option changes only latency/accuracy tuning.
- Batch SSE partials never insert before the final event.
- Disconnect before SSE done inserts nothing and offers retry.
- Detected languages appear only for gpt-transcribe results.
- Local and OpenRouter modes send none of the new OpenAI fields.
```

- [ ] **Step 4: Run docs/public checks**

Run:

```bash
bash scripts/verify-docs.sh
bash scripts/test-public-readiness.sh
```

Expected: both pass.

- [ ] **Step 5: Commit**

```bash
git add README.md CONTRIBUTING.md docs/testing-matrix.md scripts/verify-docs.sh
git commit -m "docs: document new transcription workflows"
```

### Task 12: Full regression and release-readiness verification

**Files:**

- Modify only files required to fix failures introduced by Tasks 1–11.

- [ ] **Step 1: Regenerate the project**

Run:

```bash
xcodegen generate
```

Expected: `Talkie.xcodeproj` is generated successfully and remains ignored.

- [ ] **Step 2: Run all deterministic logic tests**

Run:

```bash
xcodebuild test \
  -project Talkie.xcodeproj \
  -scheme Talkie \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/TalkieTranscriptionModelsDerivedData \
  -resultBundlePath /tmp/TalkieTranscriptionModelsTests.xcresult \
  -skip-testing:TalkieUITests \
  -skip-testing:TalkieHostIntegrationTests \
  -skip-testing:TalkieTests/ReleaseConfigurationTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 3: Run all deterministic UI tests**

Run:

```bash
xcodebuild test \
  -project Talkie.xcodeproj \
  -scheme Talkie \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/TalkieTranscriptionModelsUIDerivedData \
  -resultBundlePath /tmp/TalkieTranscriptionModelsUITests.xcresult \
  -only-testing:TalkieUITests \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 4: Run portable configuration and public checks**

Run:

```bash
bash scripts/verify-project-config.sh
bash scripts/test-release-pipeline.sh
bash scripts/verify-docs.sh
bash scripts/test-public-readiness.sh
```

Expected: all scripts exit 0.

- [ ] **Step 5: Run privacy scans**

Run:

```bash
bash scripts/scan-sensitive-content.sh
rg -n "transcript|prompt|keyword|clipboard|api.?key" Talkie \
  | rg "NSLog|print\\(|Logger\\.|diagnostic"
```

Expected: the scan passes, and manual review confirms no diagnostic logs the
contents of transcripts, prompts, keywords, clipboard data, or keys.

- [ ] **Step 6: Review the final diff**

Run:

```bash
git status --short
git diff --check
git diff --stat main...HEAD
git log --oneline main..HEAD
```

Expected: no whitespace errors, only model-integration files changed, and the
history consists of small task commits.

- [ ] **Step 7: Commit verification-only fixes**

If verification required code or test fixes:

```bash
git status --short
git add Talkie TalkieTests TalkieUITests scripts docs README.md CONTRIBUTING.md
git diff --cached --stat
git commit -m "test: complete transcription model verification"
```

Before committing, confirm every staged path appears in the failed verification
output and unstage any unrelated path with `git restore --staged PATH`. If no fixes
were needed, do not create an empty commit.

## Completion criteria

- Fresh installations use `gpt-transcribe` for batch and
  `gpt-live-transcribe` for Instant.
- Existing explicit legacy selections survive upgrade.
- Legacy models remain selectable and use legacy request fields.
- New models receive prompt, keyword, and plural-language context.
- Instant exposes all documented delay levels.
- Batch SSE progress never becomes an inserted result before the final event.
- `item_id` ordering and current finalization regression coverage remain green.
- Detected languages are stored separately from configured output language.
- Cost estimates use `$0.0045/min` and `$0.017/min`.
- OpenRouter and local transcription behavior is unchanged.
- Routine CI remains credential-free and network-free.
- Live verification is opt-in, bounded, non-sensitive, and covers JSON, SSE, and
  Realtime paths.
