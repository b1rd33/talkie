# Contributing to Talkie

Thank you for helping improve Talkie. Keep changes focused, protect user data, and include tests for behavior changes.

## Development setup

Talkie is a macOS 14+ SwiftUI and AppKit application. Install Xcode and XcodeGen, then generate the Xcode project from the tracked configuration:

```bash
brew install xcodegen
xcodegen generate
```

`project.yml` is the source of truth. Run `xcodegen generate` after every change to it. `Talkie.xcodeproj` and its resolved package file are generated locally and are not committed.

The Swift packages must remain pinned to the exact versions declared in `project.yml`:

- FluidAudio `0.15.5`
- HotKey `0.2.1`

Do not replace these `exactVersion` pins with ranges. If a dependency update is intentional, update the pin, regenerate the project, and explain the compatibility and license review in the pull request.

## Build

Generate the project before building:

```bash
xcodegen generate
xcodebuild -project Talkie.xcodeproj -scheme Talkie -configuration Debug build
```

Run the portable configuration check after changing project or signing configuration:

```bash
scripts/verify-project-config.sh
```

## Test

Routine tests must be deterministic and must not make live OpenAI, OpenRouter, or other provider calls. Use fakes or fixtures for provider behavior. `scripts/live-verify.sh` is an explicit, credentialed smoke check and is not part of routine testing.

The logic command used by CI is:

```bash
set -o pipefail
xcodebuild test \
  -project Talkie.xcodeproj \
  -scheme Talkie \
  -destination 'platform=macOS' \
  -derivedDataPath "$RUNNER_TEMP/TalkieDerivedData" \
  -resultBundlePath "$RUNNER_TEMP/TalkieTests.xcresult" \
  -skip-testing:TalkieUITests \
  -skip-testing:TalkieHostIntegrationTests \
  -skip-testing:TalkieTests/ReleaseConfigurationTests \
  CODE_SIGNING_ALLOWED=NO \
  | tee "$RUNNER_TEMP/xcodebuild.log"
```

The UI command used by CI is:

```bash
set -o pipefail
xcodebuild test \
  -project Talkie.xcodeproj \
  -scheme Talkie \
  -destination 'platform=macOS' \
  -derivedDataPath "$RUNNER_TEMP/TalkieUIDerivedData" \
  -resultBundlePath "$RUNNER_TEMP/TalkieUITests.xcresult" \
  -only-testing:TalkieUITests \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= \
  | tee "$RUNNER_TEMP/xcodebuild-ui.log"
```

GitHub Actions provides `RUNNER_TEMP`; set it to a writable temporary directory when reproducing these commands locally. Changes to the real focus and insertion stack may also require the signed host integration checks in `scripts/host-integration.sh` and the relevant manual checks in `docs/testing-matrix.md`.

## Privacy and accessibility

Never log or commit transcripts, clipboard contents, credentials, API keys, selected or surrounding text, recordings, or other personal data. Use synthetic, non-sensitive fixtures in tests and bug reports.

For UI changes, verify keyboard and assistive-technology accessibility, clear labels and focus behavior, and legibility with accessibility display settings. Check both standard motion and Reduce Motion behavior; repeating animation must stop when Reduce Motion is enabled.

## Pull requests

Before opening a pull request:

1. Regenerate the project and run `scripts/verify-project-config.sh`.
2. Run the logic suite and, for UI changes, the UI suite.
3. Add or update tests for changed behavior.
4. Describe the user-visible change, verification performed, and any privacy, accessibility, provider, package, or signing impact.
5. Keep unrelated formatting or refactoring out of the pull request.

By contributing, you agree to follow `CODE_OF_CONDUCT.md`.
