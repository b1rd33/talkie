# Native Pill Lab and App Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Debug-only native SwiftUI Pill Lab that renders the real Talkie pill with deterministic Calm Flow animations, and generate a complete Native Depth macOS AppIcon set from Swift/Core Graphics.

**Architecture:** Refactor `FlowBarView` around a value-based `PillPresentation` and a small audio-level protocol. Production adapters map coordinator, recorder, and settings into that model; the Pill Lab drives the same renderer with an in-memory simulator. Debug-only window wiring and static Release assertions prevent lab code from shipping.

**Tech Stack:** Swift 5.10, SwiftUI, AppKit, Core Graphics, XCTest, XCUITest, XcodeGen.

---

## File map

- Create `Talkie/UI/FlowBar/PillPresentation.swift`: render-only state and production mapping.
- Create `Talkie/UI/FlowBar/PillMotionProfile.swift`: Calm Flow and Reduce Motion constants.
- Create `Talkie/UI/FlowBar/AudioLevelSource.swift`: minimal production/test waveform interface.
- Modify `Talkie/UI/FlowBar/FlowBarView.swift`: render presentation values and Calm Flow transitions.
- Modify `Talkie/UI/FlowBar/WaveformCanvasView.swift`: accept the level-source interface and fixed test clock input.
- Modify `Talkie/UI/FlowBar/FlowBarPanel.swift`: construct the shared presentation renderer and expose a detachable lab panel in Debug.
- Create `Talkie/UI/PillLab/PillLabModel.swift`: ephemeral lab controls and deterministic simulator.
- Create `Talkie/UI/PillLab/PillLabView.swift`: native preview and controls.
- Create `Talkie/UI/PillLab/PillLabWindow.swift`: Debug-only standard/detached windows.
- Modify `Talkie/App/TalkieApp.swift`: Debug-only scene and menu entry.
- Create `Tools/generate_talkie_icon.swift`: Core Graphics Native Depth renderer.
- Modify `Talkie/Assets.xcassets/AppIcon.appiconset/*.png`: generated icon slots.
- Create `TalkieTests/PillPresentationTests.swift`, `PillMotionProfileTests.swift`, `SimulatedAudioLevelSourceTests.swift`, and `AppIconAssetTests.swift`.
- Create `TalkieUITests/PillLabUITests.swift`.
- Modify `scripts/verify-project-config.sh`: Release exclusion assertions.
- Modify `project.yml` only if explicit source exclusions are required after generation.

### Task 1: Value-based pill presentation

**Files:**
- Create: `Talkie/UI/FlowBar/PillPresentation.swift`
- Test: `TalkieTests/PillPresentationTests.swift`

- [ ] **Step 1: Write failing mapping tests**

```swift
func testRecordingPresentationCarriesElapsedLevelAndWarnings() {
    let value = PillPresentation(state: .recording(handsFree: false), style: .frostedGlass,
                                 elapsed: 4, audioLevel: 0.42, errorMessage: nil,
                                 offline: true, cleanupDegraded: false,
                                 reduceMotion: false, increasedContrast: false)
    XCTAssertEqual(value.statusLabel, nil)
    XCTAssertTrue(value.isActive)
    XCTAssertEqual(value.audioLevel, 0.42)
}

func testProcessingLabelsAreSpecific() {
    XCTAssertEqual(PillPresentation.preview(.transcribing).statusLabel, "Transcribing…")
    XCTAssertEqual(PillPresentation.preview(.cleaning).statusLabel, "Cleaning…")
    XCTAssertEqual(PillPresentation.preview(.inserting).statusLabel, "Inserting…")
}
```

- [ ] **Step 2: Run the focused tests and confirm RED**

Run: `xcodebuild test -project Talkie.xcodeproj -scheme Talkie -destination 'platform=macOS' -only-testing:TalkieTests/PillPresentationTests`

Expected: compilation fails because `PillPresentation` does not exist.

- [ ] **Step 3: Implement the minimal Sendable presentation model**

```swift
struct PillPresentation: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case idle, recording(handsFree: Bool), transcribing, cleaning, inserting, success, error
    }
    var state: State
    var style: PillStyle
    var elapsed: TimeInterval
    var audioLevel: Float
    var errorMessage: String?
    var offline: Bool
    var cleanupDegraded: Bool
    var reduceMotion: Bool
    var increasedContrast: Bool
}
```

Add computed `statusLabel`, `isActive`, and deterministic `preview(_:)` helpers. Keep transcript and context fields impossible to represent.

- [ ] **Step 4: Re-run focused tests and confirm GREEN**

- [ ] **Step 5: Commit**

```bash
git add Talkie/UI/FlowBar/PillPresentation.swift TalkieTests/PillPresentationTests.swift
git commit -m "refactor: add value-based pill presentation"
```

### Task 2: Calm Flow motion profiles

**Files:**
- Create: `Talkie/UI/FlowBar/PillMotionProfile.swift`
- Test: `TalkieTests/PillMotionProfileTests.swift`

- [ ] **Step 1: Write failing tests for Calm Flow and Reduce Motion**

```swift
func testCalmFlowUsesBoundedSubtleScale() {
    let profile = PillMotionProfile.calmFlow
    XCTAssertEqual(profile.handsFreeMinimumScale, 0.985, accuracy: 0.0001)
    XCTAssertEqual(profile.handsFreeMaximumScale, 1.015, accuracy: 0.0001)
    XCTAssertEqual(profile.waveformFPS, 30)
}

func testReduceMotionKeepsGeometryStable() {
    let profile = PillMotionProfile.resolve(reduceMotion: true)
    XCTAssertEqual(profile.entryMinimumScale, 1)
    XCTAssertEqual(profile.handsFreeMaximumScale, 1)
    XCTAssertFalse(profile.animatesWaveformGeometry)
}
```

- [ ] **Step 2: Confirm RED with the focused Xcode test command**

- [ ] **Step 3: Implement immutable motion constants and resolver**

Use `Duration`/`Double` values for entry duration, success duration, breath duration, scale bounds, waveform FPS, and whether waveform geometry animates. Do not embed animations or timers in the profile.

- [ ] **Step 4: Confirm GREEN and run existing `FlowBarViewTests`, `PillLayoutTests`, and `PillVisibilityPolicyTests`**

- [ ] **Step 5: Commit**

```bash
git add Talkie/UI/FlowBar/PillMotionProfile.swift TalkieTests/PillMotionProfileTests.swift
git commit -m "feat: define calm flow pill motion profiles"
```

### Task 3: Deterministic audio-level source

**Files:**
- Create: `Talkie/UI/FlowBar/AudioLevelSource.swift`
- Modify: `Talkie/UI/FlowBar/WaveformCanvasView.swift`
- Create: `TalkieTests/SimulatedAudioLevelSourceTests.swift`

- [ ] **Step 1: Write failing determinism and bounds tests**

```swift
func testSameSeedProducesSameConversationFixture() {
    let a = SimulatedAudioLevelSource(seed: 42, fixture: .conversation)
    let b = SimulatedAudioLevelSource(seed: 42, fixture: .conversation)
    XCTAssertEqual((0..<120).map { a.level(atFrame: $0) },
                   (0..<120).map { b.level(atFrame: $0) })
}

func testEveryFixtureIsNormalized() {
    for fixture in SimulatedAudioFixture.allCases {
        let source = SimulatedAudioLevelSource(seed: 9, fixture: fixture)
        XCTAssertTrue((0..<300).allSatisfy { (0...1).contains(source.level(atFrame: $0)) })
    }
}
```

- [ ] **Step 2: Confirm RED**

- [ ] **Step 3: Add `AudioLevelReading` and production adapter**

```swift
protocol AudioLevelReading: AnyObject { var latestLevel: Float { get } }
extension AudioRecorder: AudioLevelReading {}
```

Implement a seeded integer generator plus silence/conversation/energetic fixtures. Make `WaveformCanvasView` depend on `any AudioLevelReading`, retaining the existing common-mode 30 fps timer.

- [ ] **Step 4: Confirm GREEN and run the waveform smoother tests**

- [ ] **Step 5: Commit**

```bash
git add Talkie/UI/FlowBar/AudioLevelSource.swift Talkie/UI/FlowBar/WaveformCanvasView.swift TalkieTests/SimulatedAudioLevelSourceTests.swift
git commit -m "refactor: inject deterministic pill audio levels"
```

### Task 4: Shared native pill renderer and accessibility

**Files:**
- Modify: `Talkie/UI/FlowBar/FlowBarView.swift`
- Modify: `Talkie/UI/FlowBar/FlowBarPanel.swift`
- Test: `TalkieTests/FlowBarViewTests.swift`

- [ ] **Step 1: Add failing tests for accessibility labels and render policy**

Test that each presentation state returns a privacy-safe accessibility label, decorative waveform content is omitted, error text is bounded, and Reduce Motion selects stable geometry.

- [ ] **Step 2: Confirm RED**

- [ ] **Step 3: Refactor `FlowBarView` to accept a `PillPresentation` provider and level source**

Keep a compatibility production initializer so `FlowBarPanel` can map current coordinator/settings values without changing application behavior. Apply:

```swift
.animation(presentation.reduceMotion ? .easeOut(duration: 0.12)
                                    : .spring(duration: 0.35),
           value: presentation.state)
.accessibilityElement(children: .ignore)
.accessibilityLabel(presentation.accessibilityLabel)
```

Use Soft Settle only for state entry/exit, Floating Wave only while recording, and a 0.985–1.015 breath only for hands-free. Preserve the 800 ms checkmark and fixed 260 × 56 frame.

- [ ] **Step 4: Run focused pill tests and confirm GREEN**

- [ ] **Step 5: Build and launch a Debug smoke build**

Run: `xcodebuild build -project Talkie.xcodeproj -scheme Talkie -configuration Debug -destination 'platform=macOS'`

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add Talkie/UI/FlowBar/FlowBarView.swift Talkie/UI/FlowBar/FlowBarPanel.swift TalkieTests/FlowBarViewTests.swift
git commit -m "feat: render calm flow pill from presentation state"
```

### Task 5: Debug-only native Pill Lab

**Files:**
- Create: `Talkie/UI/PillLab/PillLabModel.swift`
- Create: `Talkie/UI/PillLab/PillLabView.swift`
- Create: `Talkie/UI/PillLab/PillLabWindow.swift`
- Modify: `Talkie/App/TalkieApp.swift`
- Create: `TalkieTests/PillLabModelTests.swift`
- Create: `TalkieUITests/PillLabUITests.swift`

- [ ] **Step 1: Write failing model tests**

Test production defaults, state transitions, reset behavior, non-persistence, fixture changes, and automatic Minimal Motion when Reduce Motion is enabled.

- [ ] **Step 2: Confirm RED**

- [ ] **Step 3: Implement `@Observable @MainActor PillLabModel` under `#if DEBUG`**

Expose state/style/fixture/background/position/reduce-motion/speed/intensity properties. Clamp speed to `0.5...2` and intensity to `0...1`; keep all values in memory.

- [ ] **Step 4: Implement the separate SwiftUI window**

Use a two-column layout: live `FlowBarView` preview on the left and native Form controls on the right. Add accessibility identifiers `pill-lab-window`, `pill-lab-preview`, `pill-lab-state`, `pill-lab-style`, `pill-lab-motion`, `pill-lab-detach`, and `pill-lab-reset`.

- [ ] **Step 5: Wire Debug-only scene and launch argument**

Add a `Window("Pill Lab", id: "pill-lab")` inside `#if DEBUG`. On launch, open it when arguments contain `--pill-lab`. Add a Debug-only menu button. Do not add a production defaults key.

- [ ] **Step 6: Add UI tests for launch, controls, cancel, and reset**

Launch with `--pill-lab --e2e`, assert the window and preview exist, switch every state/style, detach/close the panel, and verify Reset.

- [ ] **Step 7: Confirm unit and UI tests GREEN**

- [ ] **Step 8: Commit**

```bash
git add Talkie/UI/PillLab Talkie/App/TalkieApp.swift TalkieTests/PillLabModelTests.swift TalkieUITests/PillLabUITests.swift
git commit -m "feat: add native debug pill lab"
```

### Task 6: Native rendering checkpoints and release exclusion

**Files:**
- Create: `TalkieTests/PillRenderingTests.swift`
- Modify: `scripts/verify-project-config.sh`

- [ ] **Step 1: Add deterministic rendering tests**

Render fixed timestamps with `ImageRenderer`/`NSHostingView` for every style and meaningful state. Assert canvas size, non-empty pixel bounds, stable frame, light/dark contrast, and identical Reduce Motion frames at different motion phases.

- [ ] **Step 2: Add Release static assertions**

Extend `verify-project-config.sh` to build Release and fail if the product strings or symbols include `--pill-lab`, `PillLabWindow`, `SimulatedAudioFixture`, or `pill-lab-window`.

- [ ] **Step 3: Run rendering tests and config verification**

Expected: all rendering tests pass and the Release artifact contains no Pill Lab entry points.

- [ ] **Step 4: Commit**

```bash
git add TalkieTests/PillRenderingTests.swift scripts/verify-project-config.sh
git commit -m "test: verify native pill rendering and release isolation"
```

### Task 7: Swift/Core Graphics Native Depth AppIcon

**Files:**
- Create: `Tools/generate_talkie_icon.swift`
- Modify: `Talkie/Assets.xcassets/AppIcon.appiconset/icon_*.png`
- Create: `TalkieTests/AppIconAssetTests.swift`

- [ ] **Step 1: Write failing asset contract tests**

Parse `Contents.json`, assert every declared filename exists, assert exact pixel dimensions, and check the generated corners/background/pill/waveform representative pixels have expected alpha/luminance relationships.

- [ ] **Step 2: Confirm RED against a temporary generated output directory**

- [ ] **Step 3: Implement deterministic native renderer**

Use `CGContext`, `CGGradient`, rounded paths, and device-RGB colors. Render a 1024 × 1024 master plus simplified small-size geometry. Accept `--output <AppIcon.appiconset path>` and refuse to write outside that exact directory.

- [ ] **Step 4: Generate all ten AppIcon PNGs**

Run: `swift Tools/generate_talkie_icon.swift --output Talkie/Assets.xcassets/AppIcon.appiconset`

Expected: ten PNG files exactly matching `Contents.json` dimensions.

- [ ] **Step 5: Inspect the 1024, 128, 32, and 16 pixel outputs**

Confirm Native Depth proportions, no clipped shadow, centered pill, and legible five-bar waveform.

- [ ] **Step 6: Run asset tests and build the app**

- [ ] **Step 7: Commit**

```bash
git add Tools/generate_talkie_icon.swift Talkie/Assets.xcassets/AppIcon.appiconset TalkieTests/AppIconAssetTests.swift
git commit -m "feat: add native depth Talkie app icon"
```

### Task 8: Full verification and native review handoff

**Files:**
- Modify: `docs/testing-matrix.md`

- [ ] **Step 1: Add Pill Lab and icon rows to the release matrix**

Record automated coverage and assisted checks for real microphone response, physical `fn`, hands-free, focus retention, multiple displays/Spaces, Dock sizes, Finder, Spotlight, and app switcher.

- [ ] **Step 2: Run the complete automated suite**

Run: `xcodebuild test -project Talkie.xcodeproj -scheme Talkie -destination 'platform=macOS'`

Expected: all routine suites pass; host integration remains opt-in unless invoked through `scripts/host-integration.sh`.

- [ ] **Step 3: Run explicit host integration**

Run: `scripts/host-integration.sh`

Expected: TextEdit, Notes, and Terminal insertion tests pass.

- [ ] **Step 4: Build and verify the ad-hoc Release artifact**

Run: `scripts/build-release-adhoc.sh`

Expected: archive/export succeeds, code-signature seal verifies, and no Debug Pill Lab symbols are present.

- [ ] **Step 5: Open the native Debug Pill Lab for user review**

Show Soft Settle, Floating Wave, Breathe, processing, success, error, all styles, backgrounds, and placements. Record any visual adjustment as a focused follow-up rather than changing motion during release verification.

- [ ] **Step 6: Run formatting and worktree checks**

Run: `git diff --check` and `git status --short`.

- [ ] **Step 7: Commit the matrix update**

```bash
git add docs/testing-matrix.md
git commit -m "docs: add native pill and icon release checks"
```
