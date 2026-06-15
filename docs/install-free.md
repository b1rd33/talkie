# Installing Talkie (free build)

Talkie is shared as a free, **ad-hoc-signed** build (no paid Apple Developer
account). It works exactly like a notarized app — the only difference is a
**one-time** "unknown developer" prompt the first time you open it.

## Install

1. **Download** `Talkie-x.y.z-adhoc.zip` from the GitHub Releases page and
   double-click it to unzip.
2. **Drag `Talkie.app` into your `Applications` folder.**
3. **Double-click Talkie.** macOS blocks it:
   *"Talkie can't be opened because Apple cannot check it for malicious software."*
   This is expected for a free build — it is not a virus warning about *this* app,
   just that it isn't notarized.
4. **Allow it:** open **System Settings → Privacy & Security**, scroll down to
   *"Talkie was blocked…"*, click **Open Anyway**, then **Open** in the dialog.
   (You only do this once.)
5. **Grant permissions** when Talkie asks:
   - **Microphone** — so it can hear you while you hold the dictation key.
   - **Accessibility** — so it can type the transcription into your apps.
6. **Add your API key** in the onboarding screen (an OpenRouter key works for
   transcription + cleanup; instant streaming additionally needs an OpenAI key).

That's it — hold **fn** and speak.

## Updating

There's no auto-update in the free build. To update: download the new zip,
delete the old `Talkie.app` from Applications, and drop the new one in.

> **After an update, you may need to re-enable Accessibility.** Because the free
> build isn't signed with a stable Apple identity, macOS treats each new version
> as a "new" app and can forget the Accessibility permission. If, after updating,
> dictation only copies to the clipboard instead of typing, open
> **System Settings → Privacy & Security → Accessibility** and switch Talkie back
> on. (A paid Apple Developer account would remove both this and the first-launch
> prompt — but everything works without it.)

## Maintainer: cutting a release

```bash
scripts/build-release-adhoc.sh         # → build/Talkie-<version>-adhoc.zip
```

Then create a GitHub Release and attach that zip. `spctl -a` reporting
`rejected` for the build is **expected and correct** (it's un-notarized); the
zip still launches after the one-time Privacy & Security override above.
