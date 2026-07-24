# Installing the advanced ad-hoc build

Talkie's current public archive is **ad-hoc signed and not notarized**. This is
an advanced, unsupported installation path while a notarized build is planned.
macOS requires a manual Gatekeeper override, and replacing the app can invalidate
its Accessibility grant.

## Install

1. **Download** `Talkie-x.y.z-adhoc.zip` from the GitHub Releases page and
   double-click it to unzip.
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

There's no auto-update in the current ad-hoc release. To update: download the
new zip, delete the old `Talkie.app` from Applications, and drop the new one in.

> **After an update, you may need to re-enable Accessibility.** Because the ad-hoc
> build isn't signed with a stable Apple identity, macOS treats each new version
> as a "new" app and can forget the Accessibility permission. If, after updating,
> dictation only copies to the clipboard instead of typing, open
> **System Settings → Privacy & Security → Accessibility** and switch Talkie back
> on.

## Maintainer: cutting a release

```bash
scripts/build-release-adhoc.sh         # → build/Talkie-<version>-adhoc.zip
```

Then create a GitHub Release and attach that zip. `spctl -a` reporting
`rejected` for the build is **expected and correct** (it's un-notarized); the
zip still launches after the one-time Privacy & Security override above.
