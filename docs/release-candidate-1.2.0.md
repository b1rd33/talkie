# Talkie 1.2.0 release candidate

Status: **not released; not signed with Developer ID or notarized**.
Audit date: 2026-09-22. Branch: `codex/next-release-polish`.

## Integration base

- Main: `27e70af` (1.1.0 candidate, PR #15).
- This branch starts at `8b9f8d6`, the current head of open PR #17, which depends
  on open PR #16. Neither PR was merged during this task.
- Version prepared: 1.2.0, build 9. No release tag has been created.
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
is claimed. The user's later build-5 history includes successful short English dictations as
well as failures. Build 6 replaces AVAudioEngine capture with AVCaptureSession
and fixes a regression-test-confirmed loss of buffered PCM when formats change.
Fresh end-to-end AirPods dictation on build 6 remains under verification.

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

## Build 6 microphone and window follow-up

- Native `AVCaptureSession` selects the resolved microphone by stable UID and
  delivers PCM with its actual format; capture stops and drains callbacks before
  finalizing audio. The old AudioUnit reconfiguration/exception bridge is removed.
- A regression using integer PCM at 24 and 48 kHz exposed loss of buffered
  speech on format changes. The resampler now drains before switching formats.
- Thinking Orb includes an input waveform. Startup is labelled separately;
  errors show a red message for eight seconds and can be dismissed or retried.
- Failed/cancelled processing keeps the captured duration and audio-health result.
- Home/Settings join the active full-screen Space. Advanced settings use a segmented
  section picker inside the content area, preserving the window title bar.
- Local transcription and downloads are removed. Persisted offline configurations
  remain blocked until the user explicitly selects a cloud profile.
- Focused capture/conversion/device-selection regression: 19 tests passed.
  Result: `/tmp/talkie-native-capture-tests-v2.xcresult`.
- Integrated build-6 regression: 445 logic/rendering tests passed, zero failures;
  both Settings UI tests passed with grouped Advanced tabs. Results:
  `/tmp/talkie-build6-regression.xcresult`, `/tmp/talkie-build6-settings.xcresult`.
- Project configuration, dependency mirror and sensitive-content checks passed.
- Manual build-6 UI verification exposed collapsed native tabs after reopening.
  Build 7 replaces that native TabView with a segmented section picker.
- Installed build 6 retained both microphone and app-control permissions, and
  Settings opened from a full-screen Finder window.
- Build 7: both Settings UI tests passed (`/tmp/talkie-build7-settings.xcresult`),
  ReleaseAdhoc build and strict local Apple Development signature checks passed.
  The signed app is installed at `/Applications/Talkie.app`; builds 5 and 6 are
  retained as rollback backups.
- Computer Use confirmed build 7 still reports Microphone and Accessibility
  Granted. The five-second native capture check detected input on the current
  system-default MacBook Pro microphone; diagnostics show mono 48 kHz PCM.
  AirPods were not the active system-default microphone in that check.
- A fresh human dictation test remains pending; an input-level check alone does
  not establish end-to-end transcription reliability.
- User verification: after installing build 7, the user dictated the requested
  test sentence and confirmed that the text appeared correctly. This verifies
  the current MacBook Pro microphone end to end; AirPods were not active.
- GitHub `logic-and-ui` passed for code head `21f9cdf` (3m26s); later documentation
  commits only record installed-build evidence.

## Build 8 orb feedback

- Removed the separate waveform beside Thinking Orb at the user's request.
  The sphere itself responds to microphone loudness, with a quicker attack,
  gentle decay and a wider visible pulse. Reduce Motion still keeps it still.
- The capture and transcription pipeline is unchanged from the user-verified
  build 7.
- All 10 existing native pill-rendering tests passed, including orb motion and
  Reduce Motion (`/tmp/talkie-build8-orb-tests.xcresult`).

## Build 9 appearance controls

- The orb panel is ordered out at idle, including startup; the idle renderer
  is also empty. Recording, processing, errors and the completion exit remain visible.
- Appearance exposes all nine installed ThinkingOrbsKit designs plus Automatic,
  and a persisted 28–96 pt size slider with live preview. Panel bounds include the
  loudest audio pulse, and positioning uses those bounds without querying AppKit's
  transient window size. No new dependency or capture changes.
- Settings uses native Liquid Glass buttons/navigation on macOS 26+, larger
  system controls and a 660×640 content area. Older systems use native bordered buttons.
- 447 logic/rendering tests passed, including idle visibility and bounded panel
  sizing (`/tmp/talkie-build9-regression.xcresult`).
- Both Settings UI tests passed, including animation selection and the size
  control (`/tmp/talkie-build9-settings-v2.xcresult`). Settings window sizing is
  explicit before centering, preventing its initial hosting-view size jump.
- ReleaseAdhoc build and strict development-signature verification passed.
  Build 9 is installed at `/Applications/Talkie.app`; build 8 is preserved as
  `build/local-install/Talkie-before-appearance-controls.app.backup`.
- Computer Use confirmed the refreshed Settings, animation/size controls and
  retained Microphone/Accessibility grants. Capture code is unchanged.
