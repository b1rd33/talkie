# Changelog

## [Unreleased]

### Added

- Native organic pill styles, privacy and provider data-flow documentation, and public community guidance.
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

## [1.0.0] - 2026-06-15

### Added

- Initial public ad-hoc macOS release.
