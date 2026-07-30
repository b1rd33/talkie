# Calm Pill Processing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the native dictation pill calmer by removing the yellow Instant badge, unifying post-release presentation, shortening success feedback, and recording privacy-safe realtime fallback categories.

**Architecture:** Keep `DictationCoordinator`'s operational states intact and add a coarser `PillPresentation.VisualPhase` solely for animation identity. `FlowBarView` owns the delayed visual-label task because it is presentation timing, while `PillMotionProfile` owns shared duration constants. A typed diagnostics closure on `DictationCoordinator` makes fallback reporting testable without exposing error payloads.

**Tech Stack:** Swift 5, SwiftUI, AppKit, Observation, OSLog, XCTest, Xcode 27.

---

### Task 1: Unified processing presentation

**Files:**
- Modify: `Talkie/UI/FlowBar/PillPresentation.swift`
- Modify: `TalkieTests/PillPresentationTests.swift`

- [ ] **Step 1: Write failing visual-phase and label tests**

Add tests asserting that `transcribing`, `cleaning`, and `inserting` all map to
`.processing`, and that their visible label is either absent or `Processing…`
according to `showsProcessingLabel`.

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
xcodebuild test -project Talkie.xcodeproj -scheme Talkie -destination 'platform=macOS' -only-testing:TalkieTests/PillPresentationTests
```

Expected: compilation fails because `visualPhase` and
`showsProcessingLabel` do not exist.

- [ ] **Step 3: Implement the minimal presentation model**

Add:

```swift
enum VisualPhase: Equatable, Sendable {
    case idle, recording, processing, success, error
}

var showsProcessingLabel = false

var visualPhase: VisualPhase {
    switch state {
    case .idle: .idle
    case .recording: .recording
    case .transcribing, .cleaning, .inserting: .processing
    case .success: .success
    case .error: .error
    }
}
```

Make `statusLabel` return `Processing…` only while a processing state has
`showsProcessingLabel == true`. Keep state-specific accessibility labels.

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run the Task 1 command and expect zero failures.

### Task 2: Calm feedback timing and renderer

**Files:**
- Modify: `Talkie/UI/FlowBar/PillMotionProfile.swift`
- Modify: `Talkie/UI/FlowBar/FlowBarView.swift`
- Modify: `TalkieTests/PillMotionProfileTests.swift`
- Modify: `TalkieTests/PillRenderingTests.swift`

- [ ] **Step 1: Write failing timing tests**

Change expectations to:

```swift
XCTAssertEqual(profile.processingLabelDelay, 0.65, accuracy: 0.0001)
XCTAssertEqual(profile.successDuration, 0.4, accuracy: 0.0001)
XCTAssertEqual(profile.completionPanelDuration, 0.6, accuracy: 0.0001)
XCTAssertEqual(profile.entryDuration, 0.18, accuracy: 0.0001)
XCTAssertEqual(profile.entryMinimumScale, 0.92, accuracy: 0.0001)
```

- [ ] **Step 2: Run motion tests and verify RED**

Run:

```bash
xcodebuild test -project Talkie.xcodeproj -scheme Talkie -destination 'platform=macOS' -only-testing:TalkieTests/PillMotionProfileTests
```

Expected: compilation fails for the new timing properties and existing duration
expectations fail.

- [ ] **Step 3: Add timing values**

Extend `PillMotionProfile` with `processingLabelDelay` and
`completionPanelDuration`, then set the calm profile to 0.65 and 0.6 seconds and
the success duration to 0.4 seconds.

- [ ] **Step 4: Implement delayed processing text**

In `FlowBarView`, keep a cancellable task and set
`showsProcessingLabel = true` only if the presentation remains in visual phase
`.processing` after 650 ms. Reset it immediately when entering or leaving that
phase.

- [ ] **Step 5: Quiet the renderer**

Remove `bolt.fill`, animate using `presentation.visualPhase`, replace the spring
with `easeOut(duration: 0.18)`, and render `Processing…` only after the delay.

- [ ] **Step 6: Shorten completion lifetime**

Use `PillMotionProfile.calmFlow.successDuration` for the local checkmark task and
`completionPanelDuration` for AppDelegate's panel visibility recheck.

- [ ] **Step 7: Run presentation, motion, and native rendering tests**

Run:

```bash
xcodebuild test -project Talkie.xcodeproj -scheme Talkie -destination 'platform=macOS' \
  -only-testing:TalkieTests/PillPresentationTests \
  -only-testing:TalkieTests/PillMotionProfileTests \
  -only-testing:TalkieTests/PillRenderingTests
```

Expected: all selected tests pass.

### Task 3: Privacy-safe realtime fallback diagnostics

**Files:**
- Modify: `Talkie/Core/DictationCoordinator.swift`
- Modify: `Talkie/App/AppDelegate.swift`
- Modify: `TalkieTests/DictationCoordinatorTests.swift`

- [ ] **Step 1: Write failing diagnostic tests**

Inject a capture closure and assert:

```swift
XCTAssertEqual(events, [.realtimeStartFallback])
XCTAssertEqual(events, [.realtimeFinishFallback])
```

The tests must not assert or store provider error strings.

- [ ] **Step 2: Run coordinator tests and verify RED**

Run:

```bash
xcodebuild test -project Talkie.xcodeproj -scheme Talkie -destination 'platform=macOS' -only-testing:TalkieTests/DictationCoordinatorTests
```

Expected: compilation fails because the diagnostic event and injected closure do
not exist.

- [ ] **Step 3: Implement typed diagnostics**

Add:

```swift
enum DictationDiagnosticEvent: String, Equatable, Sendable {
    case realtimeStartFallback
    case realtimeFinishFallback
}
```

Inject a closure with a no-op default. Emit only the enum value in the two
fallback branches.

- [ ] **Step 4: Connect production logging**

Pass a closure from `AppDelegate` that logs the enum's fixed raw value with
`Logger` using public privacy. Do not pass the caught error.

- [ ] **Step 5: Run coordinator tests and verify GREEN**

Run the Task 3 command and expect zero failures.

### Task 4: Full verification and native launch

**Files:**
- Verify all changed production and test files.

- [ ] **Step 1: Run formatting checks**

Run:

```bash
git diff --check
```

Expected: no output.

- [ ] **Step 2: Run the complete logic suite**

Run:

```bash
xcodebuild test -project Talkie.xcodeproj -scheme Talkie -destination 'platform=macOS'
```

Expected: zero failures, allowing only the repository's documented UI skip.

- [ ] **Step 3: Build a fresh Debug app**

Run:

```bash
xcodebuild build -project Talkie.xcodeproj -scheme Talkie -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/talkie-calm-pill-build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Verify and launch**

Verify the executable and code signature, close only the currently running
user-owned Debug copy, then open
`/tmp/talkie-calm-pill-build/Build/Products/Debug/Talkie.app`.

- [ ] **Step 5: Inspect the native app**

Confirm that the app launches, the pill remains native SwiftUI, and settings
remain accessible. Live microphone interaction remains an assisted check if no
speech input is available.

- [ ] **Step 6: Commit**

Stage the specification, plan, production code, and tests, then commit with:

```bash
git commit -m "Refine dictation pill processing feedback"
```
