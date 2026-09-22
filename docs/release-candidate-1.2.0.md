# Talkie 1.2.0 release candidate

Status: **not released; not signed with Developer ID or notarized**.
Audit date: 2026-09-22. Branch: `codex/next-release-polish`.

## Integration base

- Main: `27e70af` (1.1.0 candidate, PR #15).
- This branch starts at `8b9f8d6`, the current head of open PR #17, which depends
  on open PR #16. Neither PR was merged during this task.
- Version prepared: 1.2.0, build 5. No release tag has been created.
- HotKey remains pinned to 0.2.1. FluidAudio was removed with local transcription.
- ThinkingOrbsKit is vendored from Libraries.dev commit
  `2015f0ba79a9faec351719c4a6d590a1e6bfa243`, with its MIT license bundled.

## Verified findings and fixes

- Realtime preview omitted uncommitted items, hiding GPT Live deltas until
  release. Preview now includes observed in-progress items while final output
  retains committed-turn ordering. Cancellation resumes pending finalization.
- Dictation session engines, cleanup service and focused context survived
  completion. Terminal paths now release them; History retries resolve current
  provider/privacy settings independently.
- Clipboard paste checked safety before asynchronous delays. It now captures
  app/process and field identity, rechecks before posting, restores clipboard
  on cancellation, and checks delivery and focus before optional Return.
- Append-only live typing now requires the original focused field and fails
  closed after losing it. No blind deletion is introduced.
- Speaker enrollment now validates audio health before overwriting a reference,
  uses the selected input device, and discards capture that starts after removal.
- Legacy local/offline profiles block recording and uploads across restart until
  a cloud profile is explicitly chosen. Local ASR and model-download UI are removed.
- History identifies clipboard-only recovery; existing retry, copy-last,
  language selection, profiles, dictionary/snippets and cost views are retained.
- Thinking Orb replaces Ink Line, Calm Flow Ribbon and Bare Wave. Dynamic
  Island remains; Liquid Glass replaces Frosted Glass with an older-OS fallback.
  Orb motion is verified in a nonactivating panel and stops under Reduce Motion.
- Audio capture binds the actual resolved default/fallback device. A local
  five-second microphone check identifies the device and releases capture.
- Home opens on launch/reopen, Settings opens directly, and permission repair
  registers Talkie before opening the system pane and can reveal the app in Finder.
- Host integration fixtures now use the current private session paths instead
  of the retired report argument and refuse to close already-running host apps.

Current provider contract checked against official documentation:
https://developers.openai.com/api/docs/guides/realtime-transcription
Interactive microphone checks detected AirPods input. A generated speech fixture
was recognized by the configured OpenAI batch model. With explicit user consent,
a failed 2.7-second test clip and a slowed copy were sent to the same service; both
returned empty text. The local model cache was incomplete, so no local-ASR result
is claimed. Fresh end-to-end AirPods dictation remains under verification.

## Checks

- [x] Baseline: 440 logic tests, 0 failures, 0 skips.
- [x] Intermediate regression suite: 450 tests, 0 failures, 0 skips, including
  real SwiftUI/AppKit rendering in nonactivating panels, normal ring rotation,
  stable reduced-motion ring, and audio-level responsiveness.
- [x] Release pipeline fixtures, documentation and public-readiness checks.
- [x] Versioned suite at `581fd20`: 451 tests, 0 failures, 0 skips; portable project
  configuration passed. Result: `/tmp/talkie-next-release-final.xcresult`.
- [x] Host integration test target compiled successfully (not executed).
- [x] ReleaseAdhoc archive and ZIP packaging passed strict code-seal, bundled
  legal-notice, extracted-app and checksum verification. This is a local,
  unsupported community preview, not a supported release.
- [x] CI `logic-and-ui` passed for `581fd20` in run 35667697974.
- [x] CI at `62fa7fb`: 452 logic tests passed, 0 failures, 0 skips. UI reported
  2 passes and 1 skipped Settings test; the job's green status did not prove
  complete Settings coverage.
- [x] The skip was replaced with a failure gate. CI diagnostics at `82b4d40`
  confirmed Settings exists as a native radio group; the test incorrectly
  searched for a segmented control. Its selector is now corrected.
- [x] CI at `876abc3`: 452 logic tests passed; strict Settings navigation and
  legacy model selection worked. Two additional role-specific visibility
  queries failed; these now use the controls’ explicit accessibility identifiers.
- [x] Pre-orb PR head `79c0c6a`: required GitHub checks passed.
- [x] Local orb/audio regression: 453 logic/rendering tests passed, 0 failures.
  Result: `/tmp/talkie-orbs-regression-final.xcresult`.
- [x] Both Settings UI checks passed, including the new style choices and
  microphone/permission controls. Result: `/tmp/talkie-orbs-settings-final.xcresult`.
- [x] ReleaseAdhoc build and locally development-signed app seal verified.
- [x] Computer Use confirmed visible Home/Settings and user-run microphone input.
- [x] Investigated permission failure: macOS logged a code-requirement mismatch
  against the old ad-hoc build. Reset only Talkie's Accessibility entry.
- [x] Regranted app-control access; the installed app reports both Microphone
  and Accessibility Granted after restart. Left Talkie closed after verification.
- [x] Bluetooth regression: 457 logic/rendering tests passed, including a stale
  48 kHz output bus with 24 kHz hardware, startup-exception cleanup, and streaming/
  file conversion across rate changes. Result: `/tmp/talkie-bluetooth-tests-v3.xcresult`.
- [x] Build 5 rebuilds capture engines per session, selects the current hardware
  input format, converts Objective-C startup exceptions into recoverable errors,
  and surfaces conversion errors instead of silently dropping buffers. It avoids
  resetting an already-selected Bluetooth device; 22 focused audio tests passed
  after this final adjustment. Result: `/tmp/talkie-bluetooth-final.xcresult`.
- [ ] Updated PR head must pass required CI before integration.
- [ ] Signed host insertion suite and physical Fn/focus-switch checks remain
  user-assisted checks in `docs/testing-matrix.md`.

## Release gates

The available signing identity is Apple Development. No Developer ID Application
identity was available, so the supported signing/notarization pipeline cannot
complete. A local ad-hoc community-preview artifact, if built, is not a supported
release and must not be described as notarized or Gatekeeper-approved.

The initially active GitHub account had read-only access. An already-authenticated
repository-owner account was then found and verified to have write access, without
changing the global active account. Main requires current `logic-and-ui` and
`Analyze Swift (swift, manual)` checks, including for administrators. PR #16
reports a blocked merge state. No approval or protection bypass is permitted.

## Local installation

With explicit user approval, `/Applications/Talkie.app` was replaced by build 4,
signed with the available Apple Development identity. Build 5 was subsequently
installed with the same identity, preserving build 4 in
`build/local-install/Talkie-before-bluetooth-fix.app.backup`. The original bundle is
retained at `build/local-install/Talkie-before-orbs.app.backup`. Settings and
history were preserved. Only Talkie's stale Accessibility grant was reset after
macOS diagnostics confirmed a signature mismatch; other app grants were untouched.

This local installation and PR do not require Developer ID or notarization.
Public release signing remains a separate task.
