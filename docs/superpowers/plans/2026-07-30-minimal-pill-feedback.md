# Minimal Pill Feedback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Talkie's default pill chrome with a waveform-to-neutral-ring transition and make the recording timer and visible cancel button independent, opt-in settings.

**Architecture:** `SettingsStore` persists two appearance booleans and `FlowBarView` adapts them into the privacy-safe `PillPresentation` value. `PillRendererView` remains the single native SwiftUI renderer, using one shared processing ring for transcription, cleanup, and insertion and a ring exit instead of a success checkmark. Dictation pipeline and keyboard cancellation behavior remain unchanged.

**Tech Stack:** Swift 6, SwiftUI, Observation, UserDefaults, XCTest, Xcode/macOS UI testing.

---

## File Map

- `Talkie/Data/SettingsStore.swift`: persist the two new appearance preferences.
- `Talkie/UI/Hub/SettingsView.swift`: expose timer and cancel-button toggles in Appearance.
- `Talkie/UI/FlowBar/PillPresentation.swift`: carry renderer flags without coupling rendering to settings storage.
- `Talkie/UI/FlowBar/PillMotionProfile.swift`: define ring transition, breath, and exit timings.
- `Talkie/UI/FlowBar/FlowBarView.swift`: remove processing-label/checkmark state and render the ring lifecycle.
- `Talkie/App/AppDelegate.swift`: use the shorter completion exit lifetime for panel visibility.
- `TalkieTests/SettingsStoreTests.swift`: verify default and persistence behavior.
- `TalkieTests/PillPresentationTests.swift`: verify independent visual flags and text-free processing.
- `TalkieTests/PillMotionProfileTests.swift`: verify normal and Reduced Motion ring behavior.
- `TalkieTests/PillRenderingTests.swift`: verify native output omits timer/cancel by default and uses a ring for processing/completion.
- `TalkieTests/PillVisibilityPolicyTests.swift`: update completion terminology while preserving hidden-style exit visibility.

### Task 1: Persist independent appearance controls

**Files:**
- Modify: `Talkie/Data/SettingsStore.swift`
- Modify: `TalkieTests/SettingsStoreTests.swift`

- [ ] **Step 1: Write failing defaults and round-trip tests**

Add assertions to `testNewDefaults()`:

```swift
XCTAssertFalse(store.showPillTimer)
XCTAssertFalse(store.showPillCancelButton)
```

Add:

```swift
func testPillChromePreferencesRoundTripIndependently() {
    let defaults = UserDefaults(suiteName: "talkie-tests-\(UUID().uuidString)")!
    let store = SettingsStore(defaults: defaults)
    store.showPillTimer = true
    XCTAssertTrue(SettingsStore(defaults: defaults).showPillTimer)
    XCTAssertFalse(SettingsStore(defaults: defaults).showPillCancelButton)

    store.showPillCancelButton = true
    XCTAssertTrue(SettingsStore(defaults: defaults).showPillCancelButton)
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
xcodebuild test -project Talkie.xcodeproj -scheme Talkie -destination 'platform=macOS' \
  -derivedDataPath /tmp/talkie-minimal-pill-red-settings \
  -clonedSourcePackagesDirPath /tmp/talkie-newest-build/SourcePackages \
  -only-testing:TalkieTests/SettingsStoreTests
```

Expected: compilation fails because `showPillTimer` and
`showPillCancelButton` do not exist.

- [ ] **Step 3: Add minimal persisted properties**

Add to `SettingsStore`:

```swift
var showPillTimer: Bool {
    didSet { defaults.set(showPillTimer, forKey: "showPillTimer") }
}
var showPillCancelButton: Bool {
    didSet { defaults.set(showPillCancelButton, forKey: "showPillCancelButton") }
}
```

Initialize both with explicit `object(forKey:)` checks and `false` fallback:

```swift
showPillTimer = defaults.object(forKey: "showPillTimer") as? Bool ?? false
showPillCancelButton =
    defaults.object(forKey: "showPillCancelButton") as? Bool ?? false
```

- [ ] **Step 4: Run the focused test and verify GREEN**

Run the Step 2 command. Expected: `SettingsStoreTests` pass.

- [ ] **Step 5: Commit Task 1**

```bash
git add Talkie/Data/SettingsStore.swift TalkieTests/SettingsStoreTests.swift
git commit -m "Add minimal pill appearance preferences"
```

### Task 2: Define the text-free presentation and motion contract

**Files:**
- Modify: `Talkie/UI/FlowBar/PillPresentation.swift`
- Modify: `Talkie/UI/FlowBar/PillMotionProfile.swift`
- Modify: `TalkieTests/PillPresentationTests.swift`
- Modify: `TalkieTests/PillMotionProfileTests.swift`

- [ ] **Step 1: Write failing presentation tests**

Replace the delayed processing-label test with:

```swift
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
```

Keep `isCancellable` tests unchanged because accessibility and keyboard
cancellation remain available without a visible X.

- [ ] **Step 2: Write failing motion tests**

Update `testCalmFlowUsesBoundedSubtleScale()`:

```swift
XCTAssertEqual(profile.processingBreathDuration, 1.6, accuracy: 0.0001)
XCTAssertEqual(profile.processingBreathMinimumScale, 0.97, accuracy: 0.0001)
XCTAssertEqual(profile.processingBreathMaximumScale, 1.0, accuracy: 0.0001)
XCTAssertEqual(profile.successDuration, 0.16, accuracy: 0.0001)
XCTAssertEqual(profile.completionPanelDuration, 0.18, accuracy: 0.0001)
```

Update Reduced Motion expectations:

```swift
XCTAssertEqual(profile.processingBreathDuration, 0)
XCTAssertEqual(profile.processingBreathMinimumScale, 1)
XCTAssertEqual(profile.processingBreathMaximumScale, 1)
```

- [ ] **Step 3: Run focused tests and verify RED**

Run:

```bash
xcodebuild test -project Talkie.xcodeproj -scheme Talkie -destination 'platform=macOS' \
  -derivedDataPath /tmp/talkie-minimal-pill-red-contract \
  -clonedSourcePackagesDirPath /tmp/talkie-newest-build/SourcePackages \
  -only-testing:TalkieTests/PillPresentationTests \
  -only-testing:TalkieTests/PillMotionProfileTests
```

Expected: compilation fails for the missing presentation flags and processing
breath properties.

- [ ] **Step 4: Implement the minimal value contract**

In `PillPresentation` remove `showsProcessingLabel`. Add:

```swift
var showsTimer = false
var showsCancelButton = false
```

Make processing labels permanently absent:

```swift
var statusLabel: String? { nil }
```

In `PillMotionProfile`, replace `processingLabelDelay` with:

```swift
var processingBreathDuration: TimeInterval
var processingBreathMinimumScale: Double
var processingBreathMaximumScale: Double
```

Use `(1.6, 0.97, 1.0)` in `calmFlow`, `(0, 1, 1)` in
`minimalMotion`, `successDuration = 0.16`, and
`completionPanelDuration = 0.18`.

- [ ] **Step 5: Run focused tests and verify GREEN**

Run the Step 3 command. Expected: both suites pass.

- [ ] **Step 6: Commit Task 2**

```bash
git add Talkie/UI/FlowBar/PillPresentation.swift \
  Talkie/UI/FlowBar/PillMotionProfile.swift \
  TalkieTests/PillPresentationTests.swift \
  TalkieTests/PillMotionProfileTests.swift
git commit -m "Define minimal pill motion contract"
```

### Task 3: Render waveform-to-ring-to-fade in native SwiftUI

**Files:**
- Modify: `Talkie/UI/FlowBar/FlowBarView.swift`
- Modify: `Talkie/App/AppDelegate.swift`
- Modify: `TalkieTests/PillRenderingTests.swift`
- Modify: `TalkieTests/PillVisibilityPolicyTests.swift`

- [ ] **Step 1: Write failing native rendering tests**

Add a deterministic image test proving elapsed time does not affect default
recording output:

```swift
func testMinimalRecordingHidesTimerByDefault() throws {
    var first = PillPresentation.preview(.recording(handsFree: false))
    first.reduceMotion = true
    first.elapsed = 1
    var second = first
    second.elapsed = 91
    let source = SimulatedAudioLevelSource(seed: 18, fixture: .conversation)

    let firstImage = try render(PillRendererView(
        presentation: first, levelSource: source, recordingStartedAt: nil))
    let secondImage = try render(PillRendererView(
        presentation: second, levelSource: source, recordingStartedAt: nil))
    XCTAssertEqual(firstImage.representation(using: .png, properties: [:]),
                   secondImage.representation(using: .png, properties: [:]))
}
```

Add a value-based renderer probe for cancel visibility by extracting a renderer
helper:

```swift
XCTAssertFalse(PillPresentation.preview(.recording(handsFree: false)).showsCancelButton)
```

Change the all-state native render test to continue requiring visible pixels for
`.transcribing`, `.cleaning`, `.inserting`, and `.success`, proving the thin ring
is rendered for all four states.

- [ ] **Step 2: Run the rendering suite and verify RED**

Run:

```bash
xcodebuild test -project Talkie.xcodeproj -scheme Talkie -destination 'platform=macOS' \
  -derivedDataPath /tmp/talkie-minimal-pill-red-render \
  -clonedSourcePackagesDirPath /tmp/talkie-newest-build/SourcePackages \
  -only-testing:TalkieTests/PillRenderingTests
```

Expected: the elapsed-time image comparison fails because the timer is currently
always rendered.

- [ ] **Step 3: Adapt production settings into presentation**

Remove `showProcessingLabel`, `processingLabelTask`, and
`updateProcessingLabel` from `FlowBarView`. Rename `showCheckmark` to
`showCompletionExit`, keep it only for the 160 ms ring-exit state, and pass:

```swift
showsTimer: settings?.showPillTimer ?? false,
showsCancelButton: settings?.showPillCancelButton ?? false
```

Use `PillMotionProfile.calmFlow.successDuration` for the exit-state lifetime.

- [ ] **Step 4: Add the native thin ring**

In `PillRendererView`, add `@State private var processingRingExpanded = false`
and a `processingRing` view:

```swift
Circle()
    .stroke(contentForeground.opacity(presentation.increasedContrast ? 0.9 : 0.62),
            lineWidth: presentation.increasedContrast ? 2 : 1.5)
    .frame(width: 16, height: 16)
    .scaleEffect(presentation.reduceMotion ? 1 :
        (processingRingExpanded
            ? motion.processingBreathMaximumScale
            : motion.processingBreathMinimumScale))
    .opacity(presentation.state == .success ? 0 : 1)
    .accessibilityHidden(true)
```

Render this ring for `.transcribing`, `.cleaning`, `.inserting`, and `.success`.
For processing, wrap it with `activePill` and conditionally append
`cancelButton`. For success, render only the ring with a scale-and-opacity exit;
remove every checkmark and green completion accent.

Conditionally render recording chrome:

```swift
if presentation.showsTimer { timerView }
if presentation.showsCancelButton { cancelButton }
```

Apply the same cancel condition during processing. Keep
`PillAccessibilityModifier` unchanged.

Start the ring breath only while processing and only when Reduced Motion is off.
Use `.easeInOut(duration: motion.processingBreathDuration).repeatForever()`.

- [ ] **Step 5: Shorten post-completion panel lifetime**

Keep `AppDelegate.applyPillActivity()` driven by
`PillMotionProfile.calmFlow.completionPanelDuration`; the new profile value makes
the hidden style order out after 180 ms. Update stale checkmark comments in
`AppDelegate` and `PillVisibilityPolicyTests` to “completion ring exit.”

- [ ] **Step 6: Run focused tests and verify GREEN**

Run:

```bash
xcodebuild test -project Talkie.xcodeproj -scheme Talkie -destination 'platform=macOS' \
  -derivedDataPath /tmp/talkie-minimal-pill-green-render \
  -clonedSourcePackagesDirPath /tmp/talkie-newest-build/SourcePackages \
  -only-testing:TalkieTests/PillRenderingTests \
  -only-testing:TalkieTests/PillVisibilityPolicyTests
```

Expected: both suites pass.

- [ ] **Step 7: Commit Task 3**

```bash
git add Talkie/UI/FlowBar/FlowBarView.swift Talkie/App/AppDelegate.swift \
  TalkieTests/PillRenderingTests.swift TalkieTests/PillVisibilityPolicyTests.swift
git commit -m "Render minimal waveform and processing ring"
```

### Task 4: Expose the controls and verify the whole app

**Files:**
- Modify: `Talkie/UI/Hub/SettingsView.swift`
- Test: `TalkieTests/SettingsStoreTests.swift`
- Test: `TalkieTests/PillPresentationTests.swift`
- Test: `TalkieTests/PillMotionProfileTests.swift`
- Test: `TalkieTests/PillRenderingTests.swift`

- [ ] **Step 1: Add Appearance toggles**

Immediately after the pill-style picker, add:

```swift
Toggle("Show recording timer", isOn: $settings.showPillTimer)
Toggle("Show cancel button", isOn: $settings.showPillCancelButton)
Text("Both are optional. Escape always cancels dictation even when the button is hidden.")
    .font(.caption)
    .foregroundStyle(.secondary)
```

Disable both controls when `showFlowBar` is false.

- [ ] **Step 2: Generate the project if source membership changed**

No new Swift source file is introduced, so project generation is not required.
Run `git diff --check` and verify no generated project diff exists.

- [ ] **Step 3: Run the full automated suite**

Run:

```bash
xcodebuild test -project Talkie.xcodeproj -scheme Talkie -destination 'platform=macOS' \
  -derivedDataPath /tmp/talkie-minimal-pill-tests \
  -clonedSourcePackagesDirPath /tmp/talkie-newest-build/SourcePackages
```

Expected: all logic and deterministic UI tests pass; the native Settings UI test
may report its existing environment-dependent skip.

- [ ] **Step 4: Build and verify a fresh Debug app**

Run:

```bash
xcodebuild build -project Talkie.xcodeproj -scheme Talkie -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/talkie-minimal-pill-build \
  -clonedSourcePackagesDirPath /tmp/talkie-newest-build/SourcePackages
codesign --verify --deep --strict \
  /tmp/talkie-minimal-pill-build/Build/Products/Debug/Talkie.app
```

Expected: `BUILD SUCCEEDED` and code-signature verification exits zero.

- [ ] **Step 5: Restart only the user-owned Debug app**

Resolve the exact existing user-owned Talkie process, stop only that PID, then:

```bash
open -n /tmp/talkie-minimal-pill-build/Build/Products/Debug/Talkie.app
```

Confirm the running process path points to the new build. Do not stop the
automation-owned exported app.

- [ ] **Step 6: Commit Task 4**

```bash
git add Talkie/UI/Hub/SettingsView.swift
git commit -m "Expose minimal pill appearance controls"
```

