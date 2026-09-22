# Changelog

## [Unreleased]

### 1.2.0 release candidate

- Surface live transcription deltas before the audio turn is committed; cancel
  finalization promptly and release session configuration and focused context.
- Revalidate the focused app and field after clipboard delays and before live
  typing; suppress follow-up Return when delivery is unsafe.
- Resolve current provider and privacy settings for History retries, and show
  when a completed dictation was copied for manual pasting.
- Keep Private / Offline local after speaker filtering was enabled.
- Validate voice-reference audio and honor the selected microphone, including
  cancellation during recorder startup.
- Add ThinkingOrbsKit animation and native Liquid Glass (macOS 26+), with
  reduced-motion/transparency support and a material fallback on older macOS.
  Replace Ink Line, Calm Flow Ribbon and Bare Wave with Thinking Orb; retain
  Bare Waveform and Dynamic Island.
- Rebind the recorder to the actual default or fallback microphone, and add a
  local input-level test that names the device and releases capture afterward.
- Capture microphone input through AVFoundation capture sessions using each
  buffer's actual PCM format; preserve buffered speech across sample-rate changes.
- Show microphone startup, a live input waveform beside Thinking Orb, and a
  readable, dismissible failure message. Keep the actual duration in failed history.
- Open Home and Settings in the active full-screen Space; keep Advanced tabs
  inside the Settings window so switching modes does not change its title bar.
- Open a visible Home window on launch, provide a direct Settings button, and
  improve permission recovery with app registration and a Finder shortcut.
- Include the pending speaker-filtering and reliability integration from PRs
  #16 and #17; those changes are not yet part of a published stable release.

This candidate is not a signed, notarized release. See
`docs/release-candidate-1.2.0.md` for checks and remaining gates.

## [1.1.0] - 2026-08-06

### Added

- Native organic pill styles, privacy and provider data-flow documentation, and public community guidance.
- Minimal waveform and processing-ring pill variants with configurable counter
  and cancel controls.
- A fail-closed Developer ID release pipeline with Apple notarization,
  stapling, Gatekeeper validation, deterministic ZIP/DMG checksums, and a
  credential-authenticating environment preflight.

### Changed

- Removed the retired trial and licensing system and clarified platform, provider, signing, and installation status for public use.
- Renamed new ad-hoc artifacts as advanced, unsupported community previews and
  added checksum, ZIP round-trip, and byte-for-byte bundled-legal-notice
  verification. The existing v1.0.0 asset remains an ad-hoc community preview;
  no notarized asset is currently published.
- Hardened supported-release provenance, identity and entitlement validation,
  private staging, ZIP/DMG round-trip checks, and machine-readable release
  metadata before atomic artifact promotion.

### Fixed

- Enforced fail-closed local-only transcription behavior and hardened accessibility, pill rendering, and host-integration safety checks.
- Fixed streamed transcription completion parsing and persistent history-store
  collisions.
- Prevented empty realtime or batch transcriptions from being inserted or saved
  as successful history entries, and added privacy-safe realtime failure
  categories for diagnosis.
- Preserved `gpt-live-transcribe` as the recommended instant model while using
  the no-VAD contract required by optional `gpt-realtime-whisper` sessions.

## [1.0.0] - 2026-06-15

### Added

- Initial public ad-hoc macOS release.
