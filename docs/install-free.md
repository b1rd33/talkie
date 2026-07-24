# Installing the advanced community preview

Talkie's current public archive is **ad-hoc signed and not notarized**. This is
an advanced, unsupported community-preview installation path. The supported
public standard is a Developer ID-signed, Apple-notarized release, but no such
asset is currently published. macOS requires a manual Gatekeeper override for
the current preview, and replacing the app can invalidate its Accessibility
grant.

## Install

1. **Download** the community-preview ZIP from the GitHub Releases page and
   double-click it to unzip. The existing v1.0.0 asset uses the legacy
   `Talkie-1.0.0-adhoc.zip` name; previews built by current tooling use
   `Talkie-x.y.z-community-preview-adhoc.zip`.
2. **Drag `Talkie.app` into your `Applications` folder.**
3. **Double-click Talkie.** macOS blocks it:
   *"Talkie can't be opened because Apple cannot check it for malicious software."*
   This is expected for an ad-hoc build because Apple has not notarized it. Verify
   that you downloaded the archive from this repository's GitHub Release before
   overriding Gatekeeper.
4. **Allow it:** open **System Settings → Privacy & Security**, scroll down to
   *"Talkie was blocked…"*, click **Open Anyway**, then **Open** in the dialog.
   (You only do this once.)
5. **Grant permissions** when Talkie asks:
   - **Microphone** — so it can hear you while you hold the dictation key.
   - **Accessibility** — so it can type the transcription into your apps.
6. **Add your API key** in the onboarding screen (an OpenRouter key works for
   transcription + cleanup; instant streaming additionally needs an OpenAI key).

After setup, hold **fn** and speak.

## Updating

There's no auto-update in the current community preview. To update: download
the new ZIP, delete the old `Talkie.app` from Applications, and drop the new
one in.

> **After an update, you may need to re-enable Accessibility.** Because the ad-hoc
> preview isn't signed with a stable Apple identity, macOS treats each new version
> as a "new" app and can forget the Accessibility permission. If, after updating,
> dictation only copies to the clipboard instead of typing, open
> **System Settings → Privacy & Security → Accessibility** and switch Talkie back
> on.

## Maintainer: building a community preview

```bash
scripts/build-release-adhoc.sh
# → build/community-preview-<version>/
#    Talkie-<version>-community-preview-adhoc.zip
#    SHA256SUMS
```

The script verifies ad-hoc code seals and checksums, but deliberately never runs
`spctl`, `notarytool`, or `stapler`. It does not establish Gatekeeper approval.
Gatekeeper rejection is **expected and correct** because the preview is not
notarized; the ZIP can launch only after the manual Privacy & Security override
above.

## Maintainer: producing the supported release

The supported path requires an installed Developer ID Application certificate
and Apple notarization access. Identify the full certificate label locally:

```bash
security find-identity -v -p codesigning
```

Set these values in the local shell; do not put them in tracked files:

```bash
export DEVELOPMENT_TEAM_ID
export SIGNING_IDENTITY
export NOTARY_KEYCHAIN_PROFILE
```

Create the Keychain profile once using interactive prompts, so a password is
not present in shell history:

```bash
xcrun notarytool store-credentials "$NOTARY_KEYCHAIN_PROFILE"
```

Then validate the environment and build:

```bash
scripts/release.sh --validate-environment
scripts/release.sh
```

As an alternative to a Keychain profile, unset `NOTARY_KEYCHAIN_PROFILE` and
set all three Team App Store Connect API key variables:

```bash
unset NOTARY_KEYCHAIN_PROFILE
export NOTARY_KEY_PATH
export NOTARY_KEY_ID
export NOTARY_ISSUER_ID
scripts/release.sh --validate-environment
scripts/release.sh
```

The script fails unless Apple returns `Accepted` for both the app submission and
the final DMG. It staples and validates the app before creating the final ZIP,
then staples and validates the exact submitted DMG. It also runs strict
`codesign`, Gatekeeper, and checksum verification. Successful artifacts are
written to `build/release-<version>/`; the script does not create a tag, push,
or publish a GitHub release.

An asset is supported only when this pipeline completes and its release notes
explicitly identify it as Developer ID-signed and Apple-notarized. The current
v1.0.0 asset did not go through this pipeline and remains an ad-hoc community
preview.
