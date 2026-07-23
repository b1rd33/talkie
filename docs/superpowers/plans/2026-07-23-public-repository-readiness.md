# Public Repository Readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the already-public `b1rd33/talkie` repository into a trustworthy, maintainable open-source macOS project with clean history, no obsolete secret-bearing licensing code, current product documentation, reproducible CI, and a defensible release process.

**Architecture:** Prepare one clean release candidate from the six local `main` commits, the production organic-pill work, and the current snippet/host-integration edits. Remove the retired licensing subsystem and purge its secret-bearing paths from published history, then add the repository-policy, CI, security, privacy, and release layers around the app. Publication is gated by a clean clone, deterministic tests, signed-host checks, and a manual GitHub settings checklist.

**Tech Stack:** Swift 5.10, SwiftUI/AppKit, XcodeGen, XCTest/XCUITest, GitHub Actions, GitHub repository rulesets, Dependabot, Developer ID/notarytool where credentials are available.

---

## Current-state audit (2026-07-23)

- GitHub repository `b1rd33/talkie` is already **PUBLIC**.
- `origin/main` is six commits behind local `main`; local `main` also has user-owned uncommitted snippet/host-integration work.
- `codex/native-pill-lab` contains the approved production pill work but also has a long experimental history; integrate it as one squash commit.
- Public branch `fix/instant-focus-steal-dataloss` contains diagnostic code that records the first portion of transcript text. It must not be merged and should be deleted from GitHub.
- The free app still ships an unused licensing/trial subsystem and key generator. Its HMAC secret is recoverable from public source and is printed in a source comment. Treat it as permanently compromised.
- No repository license, contribution guide, security policy, code of conduct, support policy, issue templates, pull-request template, topics, description, branch protection, or active GitHub workflow exists on `origin/main`.
- GitHub secret scanning and push protection are enabled. Dependabot security updates are disabled.
- A local CI workflow exists but has never been pushed.
- The only release is `v1.0.0`, an ad-hoc-signed, unnotarized zip with three downloads.
- Dependencies are pinned: HotKey 0.2.1 (MIT) and FluidAudio 0.15.5 (Apache-2.0).

## File map

**Remove retired product code:**

- `Talkie/Licensing/` — obsolete license key, HMAC, machine ID, trial, and entitlement types.
- `Talkie/UI/Hub/LicenseSettingsTab.swift` — hidden legacy UI.
- `tools/keygen/` — public license-key generator using the compromised secret.
- `TalkieTests/LicenseKeyTests.swift`, `TalkieTests/LicenseManagerTests.swift`, `TalkieTests/TrialManagerTests.swift`, `TalkieTests/EntitlementStoreTests.swift` — tests for removed behavior.

**Modify app code:**

- `Talkie/App/AppDelegate.swift` — remove construction/storage of legacy licensing services.
- `Talkie/UI/Onboarding/OnboardingView.swift` — delete the unreachable trial/license step.
- `Talkie/UI/Hub/SettingsView.swift` — delete legacy license comments/references.
- `Talkie/Data/KeychainStore.swift` — remove license/trial keychain item kinds.
- `Talkie/Core/DictationCoordinator.swift` and `TalkieTests/DictationCoordinatorTests.swift` — remove the obsolete entitlement gate and expired-trial cases.

**Create public project documents:**

- `LICENSE` — Apache License 2.0, recommended because it provides an explicit patent grant and is compatible with both pinned dependencies.
- `NOTICE` — Talkie copyright plus third-party acknowledgements.
- `PRIVACY.md` — precise local/cloud data-flow and retention disclosure.
- `SECURITY.md` — private vulnerability-reporting channel and supported versions.
- `CONTRIBUTING.md` — setup, branch, tests, privacy rules, and PR expectations.
- `CODE_OF_CONDUCT.md` — Contributor Covenant 2.1.
- `SUPPORT.md` — user support versus security-report routing.
- `CHANGELOG.md` — Keep a Changelog structure with the existing release and upcoming release.
- `.github/ISSUE_TEMPLATE/bug.yml`, `.github/ISSUE_TEMPLATE/feature.yml`, `.github/ISSUE_TEMPLATE/config.yml` — structured public issue intake.
- `.github/pull_request_template.md` — privacy, testing, and UI/accessibility checklist.
- `.github/dependabot.yml` — monthly Swift Package Manager and GitHub Actions updates.
- `.github/workflows/ci.yml` — least-privilege deterministic CI.
- `.github/workflows/codeql.yml` — weekly and PR Swift CodeQL analysis.

**Modify public-facing materials:**

- `README.md` — current features, screenshots, accurate data flow, build/test/release instructions, project status, and links to policies.
- `docs/install-free.md` — label ad-hoc installation as an unsupported development/community path once notarized releases exist.
- `docs/testing-matrix.md` — remove internal lab references and keep the public release checklist.
- `.gitignore` — ignore local agent/planning material, credentials, release exports, and signing files.
- `project.yml` — portable signing configuration and current version.
- `scripts/release.sh`, `scripts/build-release-adhoc.sh`, `scripts/verify-project-config.sh` — explicit release channels, checksum generation, and secret-free validation.

### Task 1: Freeze and inventory the public state

**Files:**
- Create locally only: `build/public-readiness/origin-main.bundle`
- Create locally only: `build/public-readiness/github-metadata.json`

- [ ] **Step 1: Preserve the current public Git graph before any rewrite**

Run:

```bash
mkdir -p build/public-readiness
git fetch --all --tags --prune
git bundle create build/public-readiness/origin-main.bundle --all
gh api repos/b1rd33/talkie > build/public-readiness/github-metadata.json
```

Expected: bundle verification succeeds and neither artifact is staged.

- [ ] **Step 2: Export current releases, branches, and repository settings**

Run:

```bash
gh api repos/b1rd33/talkie/branches --paginate > build/public-readiness/branches.json
gh api repos/b1rd33/talkie/releases --paginate > build/public-readiness/releases.json
gh repo view b1rd33/talkie --json visibility,defaultBranchRef,licenseInfo,description,homepageUrl > build/public-readiness/repo-view.json
```

Expected: the export records public visibility, `main`, `v1.0.0`, and the diagnostic branch.

- [ ] **Step 3: Record the exact integration inputs without modifying them**

Run:

```bash
git status --short --branch
git log --oneline origin/main..main
git log --oneline main..codex/native-pill-lab
git diff --name-status
```

Expected: six local main commits, the organic-pill branch, and the user-owned snippet/host-integration edits are all accounted for.

- [ ] **Step 4: Commit the audit record only if it contains no machine-specific paths or credentials**

Do not commit the JSON exports or bundle. Add a concise, sanitized audit summary to the PR description at Task 12 instead.

### Task 2: Consolidate the real product state on a clean release branch

**Files:**
- Modify: current uncommitted snippet and host-integration files already present on `main`
- Integrate: production changes from `codex/native-pill-lab`

- [ ] **Step 1: Move the current dirty work to its own branch without altering its contents**

Run from the main worktree:

```bash
git switch -c codex/snippet-host-integration
git add Talkie/UI/Hub/SnippetsView.swift TalkieHostIntegrationTests/HostInsertionTests.swift scripts/host-integration.sh TalkieTests/SnippetFormStateTests.swift
git commit -m "fix: harden snippet forms and host integration"
```

Expected: `.superpowers/` and `AGENTS.md` remain untracked and are not included.

- [ ] **Step 2: Create the release-candidate branch from local main**

Run:

```bash
git switch main
git switch -c release/public-readiness
git cherry-pick codex/snippet-host-integration
```

Expected: the reliability milestones plus the current snippet work are present.

- [ ] **Step 3: Integrate only the final organic-pill state as one auditable commit**

Run:

```bash
git merge --squash codex/native-pill-lab
git status --short
git commit -m "feat: add production organic pill styles"
```

Expected: final production styles and icon assets are present, while deleted Debug Pill Lab/notch code is absent from the release-candidate tip.

- [ ] **Step 4: Remove internal ideation artifacts from the public tip**

Remove from the release candidate:

```text
docs/superpowers/
design-studies/
.superpowers/
AGENTS.md
```

Keep only final app assets, user documentation, and tests. Commit:

```bash
git add -A
git commit -m "chore: remove internal planning artifacts"
```

### Task 3: Remove the obsolete license/trial system

**Files:**
- Delete: `Talkie/Licensing/`
- Delete: `Talkie/UI/Hub/LicenseSettingsTab.swift`
- Delete: `tools/keygen/`
- Delete: `TalkieTests/LicenseKeyTests.swift`
- Delete: `TalkieTests/LicenseManagerTests.swift`
- Delete: `TalkieTests/TrialManagerTests.swift`
- Delete: `TalkieTests/EntitlementStoreTests.swift`
- Modify: `Talkie/App/AppDelegate.swift`
- Modify: `Talkie/UI/Onboarding/OnboardingView.swift`
- Modify: `Talkie/UI/Hub/SettingsView.swift`
- Create: `Talkie/Data/ProjectLinks.swift`
- Modify: `Talkie/Data/KeychainStore.swift`
- Modify: `Talkie/Core/DictationCoordinator.swift`
- Modify: `TalkieTests/DictationCoordinatorTests.swift`

- [ ] **Step 1: Add a regression test proving dictation has no entitlement dependency**

In `TalkieTests/DictationCoordinatorTests.swift`, construct the coordinator without an entitlement argument and keep the existing successful-recording assertion:

```swift
func testFreeBuildStartsDictationWithoutEntitlementState() async throws {
    let harness = makeHarness()
    await harness.coordinator.press()
    XCTAssertEqual(harness.coordinator.state, .recording)
}
```

- [ ] **Step 2: Run the focused test and confirm the old constructor prevents compilation**

Run:

```bash
xcodegen generate
xcodebuild test -project Talkie.xcodeproj -scheme Talkie -destination 'platform=macOS' -only-testing:TalkieTests/DictationCoordinatorTests/testFreeBuildStartsDictationWithoutEntitlementState
```

Expected: compilation fails until the entitlement argument and gate are removed.

- [ ] **Step 3: Delete legacy services and call sites**

Remove `LicenseManager`, `TrialManager`, `EntitlementStore`, `LicenseSecret`, the license key encoder, hidden settings/onboarding views, keychain item cases, and key generator. In `DictationCoordinator`, remove the optional entitlement property and every `gateError` check; dictation availability must depend only on permissions, recorder/provider readiness, and current state.

- [ ] **Step 4: Remove obsolete tests and strings**

Run:

```bash
rg -n "LicenseSecret|LicenseManager|TrialManager|EntitlementStore|Trial expired|Start 14-day trial|license_key|trial_seal" Talkie TalkieTests tools
```

Expected: no matches.

- [ ] **Step 5: Run logic tests**

Run:

```bash
xcodebuild test -project Talkie.xcodeproj -scheme Talkie -destination 'platform=macOS' -skip-testing:TalkieUITests -skip-testing:TalkieHostIntegrationTests
```

Expected: all remaining logic tests pass.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor: remove retired licensing and trial system"
```

### Task 4: Purge the compromised licensing paths from published history

**Files/history:**
- Purge all historical versions of `Talkie/Licensing/` and `tools/keygen/`

- [ ] **Step 1: Obtain explicit maintainer approval for a force-push**

Do not continue without confirmation that rewriting the 147-commit public history is acceptable. Explain that existing clones and forks must re-clone, release tags will move, and cached copies cannot be recalled.

- [ ] **Step 2: Work from a fresh mirror clone, never the development checkout**

Run:

```bash
git push -u origin release/public-readiness
git clone --mirror https://github.com/b1rd33/talkie.git build/public-readiness/talkie-clean.git
cd build/public-readiness/talkie-clean.git
git filter-repo --path Talkie/Licensing --path tools/keygen --invert-paths --force
```

Expected: the mirror contains the release-candidate branch, and `git log --all -- Talkie/Licensing tools/keygen` returns no commits after filtering.

- [ ] **Step 3: Verify the literal and obfuscated secret are absent without printing either value**

Use a local secret-scanner rule containing the known compromised value and scan every rewritten commit. Also run:

```bash
git rev-list --objects --all | rg 'Talkie/Licensing|tools/keygen'
```

Expected: no matches and the secret scanner reports zero findings.

- [ ] **Step 4: Force-push rewritten refs during a short maintenance window**

Run only after the release-candidate tip is included in the rewritten mirror:

```bash
git push --force --mirror origin
```

Expected: GitHub `main` and retained tags point to rewritten commits. Announce that contributors must re-clone.

- [ ] **Step 5: Delete the unsafe diagnostic branch**

Run:

```bash
git push origin --delete fix/instant-focus-steal-dataloss
```

Expected: only `main` and active reviewed release branches remain on GitHub.

### Task 5: Add an explicit open-source and community policy layer

**Files:**
- Create: `LICENSE`
- Create: `NOTICE`
- Create: `SECURITY.md`
- Create: `CONTRIBUTING.md`
- Create: `CODE_OF_CONDUCT.md`
- Create: `SUPPORT.md`

- [ ] **Step 1: Add Apache-2.0 licensing**

Use the unmodified Apache License 2.0 text in `LICENSE`. Add this `NOTICE` structure:

```text
Talkie
Copyright 2026 Christian Nikolov

This product includes software developed by third parties:
- FluidAudio, Apache License 2.0
- HotKey, MIT License

See each dependency's repository and resolved package checkout for its complete license text.
```

If the maintainer does not want patent-granting open source, stop here and choose a license deliberately; public visibility alone is not an open-source license.

- [ ] **Step 2: Add a security policy**

`SECURITY.md` must state:

```markdown
# Security Policy

## Supported versions

Only the latest GitHub Release is supported with security fixes.

## Reporting a vulnerability

Use GitHub's private vulnerability reporting for this repository. Do not open a public issue for vulnerabilities or include API keys, transcripts, recordings, crash dumps, or personal data in reports.

We will acknowledge reports within 7 days and provide a remediation timeline after triage.
```

- [ ] **Step 3: Add contribution and support boundaries**

`CONTRIBUTING.md` must require XcodeGen regeneration, pinned packages, no live provider calls in routine tests, no transcript/clipboard/credential logging, accessibility and Reduce Motion checks for UI changes, and the exact logic/UI test commands. `SUPPORT.md` routes bugs to Issues, usage discussion to Discussions, and vulnerabilities to private reporting.

- [ ] **Step 4: Add Contributor Covenant 2.1**

Use the official unmodified text in `CODE_OF_CONDUCT.md`, with enforcement contact set to GitHub private reporting or a dedicated project contact that the maintainer actively monitors.

- [ ] **Step 5: Commit**

```bash
git add LICENSE NOTICE SECURITY.md CONTRIBUTING.md CODE_OF_CONDUCT.md SUPPORT.md
git commit -m "docs: add open source and community policies"
```

### Task 6: Publish an exact privacy and data-flow contract

**Files:**
- Create: `PRIVACY.md`
- Modify: `README.md`
- Modify: `Talkie/UI/Onboarding/OnboardingView.swift`
- Modify: `Talkie/UI/Hub/SettingsView.swift`

- [ ] **Step 1: Write the privacy document around four explicit modes**

`PRIVACY.md` must state:

```markdown
# Privacy

Talkie has no account system, analytics, advertising, or Talkie-operated server.

## On-device transcription
Audio stays on the Mac. Model files are downloaded from the model provider. Audio is deleted after transcription unless “Keep audio recordings” is enabled.

## Cloud batch transcription
After release, audio is sent directly from the Mac to the provider selected in Settings. Provider terms and retention policies apply.

## Instant transcription
Audio is streamed directly to OpenAI while recording. Provider terms and retention policies apply.

## Cleanup and context
Transcript text and, only when the user explicitly enables context awareness, bounded nearby editable text may be sent to the selected cleanup provider. Password and secure fields are excluded. Context is not stored by Talkie.

API keys are stored in macOS Keychain. Dictation history remains local unless the user exports or copies it.
```

Add a provider table linking to the current OpenAI, OpenRouter, and model-host privacy terms.

- [ ] **Step 2: Ensure product copy links to the policy before cloud use**

Create the single typed destination:

```swift
import Foundation

enum ProjectLinks {
    static let privacyPolicy = URL(
        string: "https://github.com/b1rd33/talkie/blob/main/PRIVACY.md"
    )!
}
```

Add `Link("Privacy and provider data flow", destination: ProjectLinks.privacyPolicy)` in onboarding and Settings. Keep the short in-app explanation consistent with `PRIVACY.md`.

- [ ] **Step 3: Add copy-level tests**

In `TalkieTests/SettingsViewLogicTests.swift`, assert that the privacy URL is HTTPS and that the four mode labels are nonempty. Keep the URL in one typed constant rather than duplicating strings.

- [ ] **Step 4: Commit**

```bash
git add PRIVACY.md README.md Talkie/Data/ProjectLinks.swift Talkie/UI/Onboarding/OnboardingView.swift Talkie/UI/Hub/SettingsView.swift TalkieTests/SettingsViewLogicTests.swift
git commit -m "docs: publish privacy and provider data flow"
```

### Task 7: Make the README match the product users will clone

**Files:**
- Modify: `README.md`
- Create: `docs/images/talkie-settings.png`
- Create: `docs/images/talkie-pill.png`
- Create: `CHANGELOG.md`

- [ ] **Step 1: Replace stale feature and release copy**

The README must include, in this order:

1. One-sentence product promise and native screenshots.
2. macOS 14+ requirements and Apple Silicon support status.
3. Install paths: notarized release first; source build second; ad-hoc build clearly labeled advanced/unsupported.
4. Core workflows: hold-to-talk, hands-free, local/cloud/instant engines, profiles, snippets, dictionary, context, transforms, language/microphone selection, history, and organic pill styles.
5. A concise provider data-flow table linking to `PRIVACY.md`.
6. Build, test, contributing, security, support, and license links.
7. Project status and known limitations.

Remove unstable price claims unless they include a checked date and a link to the provider's pricing page.

- [ ] **Step 2: Capture privacy-safe screenshots**

Use a clean macOS test account or isolated defaults. Screenshots must contain no API keys, transcript history, app names tied to personal activity, email addresses, clipboard data, or filenames. Crop out the menu bar if it contains personal data.

- [ ] **Step 3: Add a changelog**

Use Keep a Changelog headings:

```markdown
# Changelog

## [Unreleased]
### Added
### Changed
### Fixed

## [1.0.0] - 2026-06-15
### Added
- Initial public ad-hoc macOS release.
```

- [ ] **Step 4: Verify every local link**

Run:

```bash
rg -o '\[[^]]+\]\(([^)]+)\)' README.md PRIVACY.md CONTRIBUTING.md SECURITY.md SUPPORT.md
```

Open each relative target and verify it exists.

- [ ] **Step 5: Commit**

```bash
git add README.md CHANGELOG.md docs/images
git commit -m "docs: refresh public project documentation"
```

### Task 8: Harden repository hygiene and automated checks

**Files:**
- Modify: `.gitignore`
- Create: `.github/dependabot.yml`
- Modify: `.github/workflows/ci.yml`
- Create: `.github/workflows/codeql.yml`
- Modify: `scripts/verify-project-config.sh`

- [ ] **Step 1: Expand ignore rules**

Add:

```gitignore
# Local agent/planning state
.superpowers/
.worktrees/
AGENTS.md
.impeccable.md

# Credentials and signing material
.env
.env.*
*.p8
*.p12
*.pem
*.key
*.cer
*.mobileprovision
ExportOptions.local.plist

# Release and test products
build/
DerivedData/
*.xcresult
```

- [ ] **Step 2: Give CI least privilege and deterministic inputs**

At workflow top level add:

```yaml
permissions:
  contents: read

jobs:
  logic-and-ui:
    timeout-minutes: 45
```

Keep provider credentials absent, use exact dependency versions, upload `.xcresult` artifacts only on failure or with a short retention period, and add a static scan that fails on `LicenseSecret`, transcript-content diagnostics, private-key headers, and known provider-key prefixes.

- [ ] **Step 3: Pin third-party Actions by full commit SHA**

Replace mutable `@v4` tags for checkout/upload actions with reviewed commit SHAs and retain the release tag in a comment, for example:

```yaml
- uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4
- uses: actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02 # v4
```

These SHAs were resolved from the official `v4` refs on 2026-07-23. Re-resolve and review them if implementation occurs substantially later.

- [ ] **Step 4: Add Dependabot**

Create:

```yaml
version: 2
updates:
  - package-ecosystem: swift
    directory: /
    schedule:
      interval: monthly
    open-pull-requests-limit: 5
  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: monthly
    open-pull-requests-limit: 5
```

- [ ] **Step 5: Add Swift CodeQL**

Use GitHub's current official Swift CodeQL template with `languages: swift`, `runs-on: macos-26`, `permissions: security-events: write, packages: read, contents: read`, plus pull-request, push-to-main, and weekly triggers. Pin `github/codeql-action` to `4187e74d05793876e9989daffde9c3e66b4acd07` (`v3`, resolved 2026-07-23).

- [ ] **Step 6: Extend portable configuration checks**

Make `scripts/verify-project-config.sh` fail if it finds:

```text
LicenseSecret
TrialManager
PillLab
--pill-lab
YOURTEAMID
```

Also verify `LICENSE`, `PRIVACY.md`, `SECURITY.md`, and exact package versions exist.

- [ ] **Step 7: Run CI commands locally and commit**

```bash
scripts/verify-project-config.sh
xcodegen generate
xcodebuild test -project Talkie.xcodeproj -scheme Talkie -destination 'platform=macOS' -skip-testing:TalkieHostIntegrationTests
git add .gitignore .github scripts/verify-project-config.sh
git commit -m "ci: harden public repository checks"
```

### Task 9: Add structured issue and pull-request intake

**Files:**
- Create: `.github/ISSUE_TEMPLATE/bug.yml`
- Create: `.github/ISSUE_TEMPLATE/feature.yml`
- Create: `.github/ISSUE_TEMPLATE/config.yml`
- Create: `.github/pull_request_template.md`

- [ ] **Step 1: Build a privacy-safe bug form**

Required fields: Talkie version, macOS version, Mac architecture, engine mode, expected result, actual result, reproducible steps, and regression status. The form must display:

```text
Do not paste API keys, transcripts, recordings, clipboard contents, crash logs containing personal paths, or other private data.
```

- [ ] **Step 2: Build a focused feature form**

Ask for problem, proposed behavior, privacy impact, local/offline impact, and alternatives. Do not ask contributors to submit implementation details before describing the user problem.

- [ ] **Step 3: Add the PR checklist**

Require:

```markdown
- [ ] Tests cover the change and pass locally.
- [ ] No live provider calls or production credentials are required by routine tests.
- [ ] No transcript, selected text, clipboard content, recording, or API key is logged.
- [ ] UI changes were checked with keyboard access, Reduce Motion, Increase Contrast, light mode, and dark mode.
- [ ] User-facing behavior and privacy documentation are updated.
```

- [ ] **Step 4: Commit**

```bash
git add .github/ISSUE_TEMPLATE .github/pull_request_template.md
git commit -m "docs: add public issue and pull request templates"
```

### Task 10: Make the release process trustworthy

**Files:**
- Modify: `project.yml`
- Modify: `scripts/release.sh`
- Modify: `scripts/build-release-adhoc.sh`
- Modify: `scripts/ExportOptions.plist`
- Modify: `docs/install-free.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Choose the supported release channel**

Recommended public standard: Developer ID signed + Apple notarized. If the maintainer does not yet have an Apple Developer account, label ad-hoc artifacts as **community preview**, not the normal install path, and do not claim Gatekeeper trust.

- [ ] **Step 2: Remove hard-coded team identifiers and placeholders**

`project.yml` must not contain a personal development team or `YOURTEAMID`. Require release invocations to supply `DEVELOPMENT_TEAM_ID` and signing identity through the local environment:

```bash
: "${DEVELOPMENT_TEAM_ID:?Set DEVELOPMENT_TEAM_ID}"
xcodebuild archive \
  -project Talkie.xcodeproj \
  -scheme Talkie \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM_ID"
```

Copy `scripts/ExportOptions.plist` to `build/ExportOptions.resolved.plist` and set its `teamID` locally before export. Never commit the resolved file.

- [ ] **Step 3: Generate checksums and release metadata**

After packaging, run:

```bash
shasum -a 256 build/Talkie-*.zip build/Talkie-*.dmg > build/SHA256SUMS
```

Print the tag, commit SHA, Xcode version, macOS deployment target, dependency versions, notarization result, and checksum path.

- [ ] **Step 4: Verify the signed artifact**

Run:

```bash
codesign --verify --deep --strict --verbose=2 build/export/Talkie.app
spctl -a -vv build/export/Talkie.app
xcrun stapler validate build/export/Talkie.app
```

Expected for the supported release: all three pass. For an explicitly ad-hoc preview, `spctl` rejection is documented and never reported as success.

- [ ] **Step 5: Update the release docs and commit**

```bash
git add project.yml scripts/release.sh scripts/build-release-adhoc.sh scripts/ExportOptions.plist docs/install-free.md CHANGELOG.md
git commit -m "build: harden public release pipeline"
```

### Task 11: Run the public release gate from a clean clone

**Files:**
- Update: `docs/testing-matrix.md` with actual results and release version

- [ ] **Step 1: Clone the candidate as an outsider would**

```bash
git clone --no-local . /tmp/talkie-public-verification
cd /tmp/talkie-public-verification
xcodegen generate
```

Expected: no dependency on ignored local files, private planning docs, credentials, or generated Xcode project state.

- [ ] **Step 2: Run the deterministic automated suites**

```bash
scripts/verify-project-config.sh
xcodebuild test -project Talkie.xcodeproj -scheme Talkie -destination 'platform=macOS' -skip-testing:TalkieHostIntegrationTests
```

Expected: zero failures and no live OpenAI/OpenRouter requests.

- [ ] **Step 3: Run signed host integration**

```bash
scripts/host-integration.sh
```

Expected: TextEdit, Notes, and Terminal insertion pass with stubbed audio/providers and real focus/insertion behavior.

- [ ] **Step 4: Run assisted release checks**

Verify fresh install, onboarding completion and Mac restart, revoked microphone and Accessibility recovery, physical `fn`, hands-free toggle, instant focus switching, secure fields, local/offline model flow, snippets, transforms, language switching, microphone changes, each production pill style, launch at login, and update over the prior release.

- [ ] **Step 5: Run a final whole-history secret scan**

Install a pinned release of Gitleaks from its official repository, then run:

```bash
gitleaks git --redact --log-opts="--all"
gitleaks dir --redact .
```

Expected: zero findings. Review any allowlist manually; do not suppress a finding merely to make CI green.

- [ ] **Step 6: Commit the completed matrix**

```bash
git add docs/testing-matrix.md
git commit -m "test: record public release verification"
```

### Task 12: Configure GitHub governance and publish

**Files/external state:**
- GitHub repository metadata, ruleset, security settings, Discussions, release

- [ ] **Step 1: Open and review a public-readiness PR**

Push `release/public-readiness` and create a PR summarizing the history rewrite, licensing deletion, privacy contract, CI, tests, and release verification. Do not merge until Actions and CodeQL pass.

- [ ] **Step 2: Configure repository metadata**

Set:

```text
Description: Native push-to-talk dictation for macOS — local or bring-your-own cloud providers.
Topics: macos, swift, swiftui, dictation, speech-to-text, accessibility, open-source, offline-first
Website: the canonical documentation or release page, if one exists; otherwise leave blank.
```

Enable Discussions only if it will be monitored; disable Wiki and Projects unless they have a defined use.

- [ ] **Step 3: Enable security features**

Enable Dependabot alerts and security updates, private vulnerability reporting, secret scanning, push protection, non-provider pattern scanning, and validity checks where GitHub makes them available.

- [ ] **Step 4: Add a `main` ruleset**

Require pull requests, the Talkie CI and CodeQL checks, conversation resolution, linear history, and no force pushes or deletions. Permit maintainer bypass only for emergency security remediation. Apply this after the one authorized history rewrite.

- [ ] **Step 5: Merge and tag the verified release**

Merge the PR, pull the protected `main`, rerun `scripts/verify-project-config.sh`, build the supported artifact, and create an annotated semantic-version tag. Publish a GitHub Release with changelog, supported macOS/architecture, privacy summary, known limitations, checksums, and signed/notarized status.

- [ ] **Step 6: Repair the legacy release presentation**

Keep `v1.0.0` for traceability, but label it clearly as the legacy ad-hoc build and remove its “Latest” status by publishing the new verified release. Do not silently replace an existing asset under the same tag.

- [ ] **Step 7: Verify the public experience**

From a logged-out browser and a new temporary clone, confirm README images, LICENSE detection, SECURITY link, issue forms, Actions badges, release downloads, checksums, source build, and no access to deleted diagnostic branches.

## Publication acceptance criteria

- GitHub shows an explicit open-source license and complete README/privacy/security/contribution policies.
- The obsolete licensing/trial/keygen subsystem is absent from the tip and its secret-bearing paths are absent from rewritten history.
- No public branch contains transcript-content diagnostic logging.
- `main` contains the reliability milestones, current snippet/host work, and final production pill styles without experimental lab/notch implementation.
- A clean clone generates, builds, and runs deterministic tests without credentials or private files.
- Routine CI has least privilege, pinned Actions, artifact diagnostics, CodeQL, and Dependabot.
- The supported downloadable app is Developer ID signed and notarized, or explicitly labeled a community preview if it is still ad-hoc.
- Branch rules protect `main`; private vulnerability reporting, secret scanning, and push protection are enabled.
- The release notes and checksum identify exactly which commit produced each artifact.
