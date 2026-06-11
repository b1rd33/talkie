# Talkie — Release Checklist

Work top to bottom. One-time setup lives at the bottom — first release: do
that section first.

## Every release

1. [ ] **Bump versions** — `project.yml` is the only source of truth:
   - `MARKETING_VERSION`: user-facing semver (e.g. `1.0.1`)
   - `CURRENT_PROJECT_VERSION`: increment the integer — Sparkle compares
     `CFBundleVersion`, so an unbumped build number means "no update found"
   Then `xcodegen generate` and commit `project.yml` + `Talkie/Info.plist`.
2. [ ] **Full suite green:**
   ```bash
   xcodebuild test -project Talkie.xcodeproj -scheme Talkie -destination 'platform=macOS' 2>&1 | tail -5
   ```
3. [ ] **Build, notarize, staple, package:**
   ```bash
   ./scripts/release.sh
   ```
   Expect `status: Accepted` from notarytool and `accepted` from spctl.
   Artifacts: `build/Talkie-<version>.dmg` (website) and
   `build/Talkie-<version>.zip` (Sparkle).
4. [ ] **Manual test matrix** — run `docs/testing-matrix.md` against the
   stapled `build/export/Talkie.app`. All boxes, no skips.
5. [ ] **Tag:**
   ```bash
   git tag v<version>
   git push origin main --tags
   ```
6. [ ] **Appcast** — generate and sign (EdDSA key comes from the Keychain):
   ```bash
   mkdir -p ~/talkie-updates
   cp build/Talkie-<version>.zip ~/talkie-updates/
   SPARKLE_BIN="$(find ~/Library/Developer/Xcode/DerivedData -type d -path '*SourcePackages/artifacts/sparkle/Sparkle/bin' 2>/dev/null | head -1)"
   "$SPARKLE_BIN/generate_appcast" --download-url-prefix "https://updates.example.com/talkie/" ~/talkie-updates/
   ```
   (Use the real feed host from Info.plist's SUFeedURL, path included.)
7. [ ] **Upload** — `appcast.xml` + the zip to the SUFeedURL host;
   the DMG to the website download link. Verify both:
   ```bash
   curl -sI https://updates.example.com/talkie/appcast.xml | head -1
   curl -sI https://updates.example.com/talkie/Talkie-<version>.zip | head -1
   ```
8. [ ] **Update-path check** — on a machine/account running the PREVIOUS
   version: menu bar → Check for Updates… → the new version is offered,
   downloads, installs, relaunches.
9. [ ] **Clean-account smoke install** — new macOS user account: download the
   DMG (so it carries the quarantine flag), drag-install, launch, complete
   onboarding, dictate once. No Gatekeeper warning, no permission dead ends.

## One-time setup (first release only)

- [ ] Apple Developer Program membership active; note the **Team ID**
  (developer.apple.com → Membership).
- [ ] **Developer ID Application** certificate: Xcode → Settings… → Accounts →
  team → Manage Certificates… → + → Developer ID Application. Verify:
  ```bash
  security find-identity -v -p codesigning | grep "Developer ID Application"
  ```
- [ ] Team ID written into `project.yml` (`DEVELOPMENT_TEAM`) and
  `scripts/ExportOptions.plist` (`teamID`).
- [ ] Notarization profile (app-specific password from account.apple.com →
  Sign-In and Security → App-Specific Passwords):
  ```bash
  xcrun notarytool store-credentials talkie-notary \
    --apple-id <appleID> --team-id <teamID> --password <app-specific password>
  ```
- [ ] Sparkle keys generated once (`generate_keys` under the Sparkle SPM
  artifact bin, see step 6's `SPARKLE_BIN`); public key pasted into
  `project.yml` → `SUPublicEDKey`; private key backed up from the Keychain
  (`generate_keys -x <file>`) into a password manager.
- [ ] Update host serving `https://<host>/talkie/` over HTTPS; `SUFeedURL`
  in `project.yml` points at `<that path>/appcast.xml`.
- [ ] Optional hardening: also notarize the DMG itself
  (`xcrun notarytool submit build/Talkie-<version>.dmg --keychain-profile talkie-notary --wait`
  then `xcrun stapler staple build/Talkie-<version>.dmg`) — the app inside is
  already stapled, so this is belt-and-braces.
