# Talkie 1.2.0 release candidate

Status: **not released; not signed with Developer ID or notarized**.
Audit date: 2026-09-22. Branch: `codex/next-release-polish`.

## Integration base

- Main: `27e70af` (1.1.0 candidate, PR #15).
- This branch starts at `8b9f8d6`, the current head of open PR #17, which depends
  on open PR #16. Neither PR was merged during this task.
- Version prepared: 1.2.0, build 3. No release tag has been created.
- Dependency pins remain FluidAudio 0.15.5 and HotKey 0.2.1.

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
- Selecting Private / Offline disables cloud speaker filtering and preserves
  local-only behavior across restart.
- History identifies clipboard-only recovery; existing retry, copy-last,
  language selection, profiles, dictionary/snippets and cost views are retained.
- Organic styles use the smoothed microphone level instead of clamping decay
  to the initial level. Normal processing rotation remains native; Reduce Motion
  stops rotation. Idle organic views have no timer subscription.
- Host integration fixtures now use the current private session paths instead
  of the retired report argument and refuse to close already-running host apps.

Current provider contract checked against official documentation:
https://developers.openai.com/api/docs/guides/realtime-transcription
No live provider request or microphone recording was made.

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
- [ ] Current-head strict Settings UI and CodeQL checks must pass before integration.
- [ ] Local native UI suite: build succeeded; runner failed to initialize
  because macOS timed out enabling automation.
- [ ] Interactive native review: Computer Use timed out opening Talkie.
- [ ] Signed host insertion suite: requires an available desktop automation
  session and Accessibility-approved test app; not executed.
- [ ] Physical Fn, real speech, focus-switch host behavior, TCC revoke/regrant,
  fresh/completed onboarding and idle CPU observation: user-assisted checks
  remain in `docs/testing-matrix.md`.

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

One production Talkie process was observed at `/Applications/Talkie.app`.
That installed app is ad-hoc signed. Its settings, history, TCC registrations
and application bundle have not been replaced or reset. Canonical installation
alone does not provide a stable signing identity.
