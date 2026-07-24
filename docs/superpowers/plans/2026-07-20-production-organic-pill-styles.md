# Production Organic Pill Styles — Implementation Plan

> Execute on `codex/native-pill-lab`. This plan replaces the temporary Debug Pill Lab with three production-ready styles.

## 1. Extend the persisted style model

**Files:** `Talkie/Data/PillStyle.swift`, `Talkie/UI/Hub/SettingsView.swift`, `TalkieTests/SettingsStoreTests.swift`

- Add stable raw-value cases for **Ink Line**, **Calm Flow Ribbon**, and **Bare Wave**.
- Keep the existing styles and migrations intact; unknown legacy values still resolve to the existing default.
- Add the three styles to the real Appearance picker with clear names and descriptions.
- Write migration and persistence tests before implementation.

## 2. Build a shared production organic-wave renderer

**Files:** `Talkie/UI/FlowBar/OrganicWaveformView.swift` (new), `Talkie/UI/FlowBar/FlowBarView.swift`, `TalkieTests/OrganicWaveformRenderingTests.swift` (new)

- Move only the approved visual language from the Lab into a production SwiftUI `Canvas` renderer: a slender Ink Line, a layered Calm Flow Ribbon, and one continuous Bare Wave.
- Drive it from the real `AudioLevelReading` source using the existing smoothing approach and a common-mode timer so a non-activating panel animates during actual dictation.
- Respect Reduce Motion and Increased Contrast, and retain current semantic state indicators (success/error) without transcript data.
- Route recording, processing, success, and error states through the shared chromeless behavior; preserve the existing four styles unchanged.
- Add deterministic image-rendering tests for each new style and state, plus direct helper-policy tests.

## 3. Remove the Debug Pill Lab completely

**Files removed:** `Talkie/UI/PillLab/`, `TalkieTests/PillLabModelTests.swift`, `TalkieTests/PillLabMicrophoneLevelSourceTests.swift`, `TalkieTests/PillLabSpaceKeyMonitorTests.swift`, `TalkieTests/FocusedWaveformRenderingTests.swift`, `TalkieUITests/PillLabUITests.swift`, `scripts/verify-pill-lab-release.sh`, the four superseded Lab plan/spec documents.

**Files updated:** `Talkie/App/AppDelegate.swift`, `docs/testing-matrix.md`

- Delete the `--pill-lab` launch path, Debug window controller, fixture microphone source, global space monitor, UI controls, tests, release script, and their documentation.
- Replace the Lab-only manual-test entry in the matrix with concise production-style checks.
- Confirm a Release build contains neither the Lab types nor `--pill-lab` string.

## 4. Verify the production path

- Regenerate the Xcode project if required by the project manifest.
- Run focused logic/rendering tests, then the full signed test suite.
- Build the Release app and statically verify that no Debug Pill Lab symbols or launch flags remain.
- Launch the debug production app and visually inspect the Appearance picker plus each new style during a fixture/real recording flow when permission is available.
