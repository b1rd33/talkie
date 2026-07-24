# Talkie — Manual Release Test Matrix

Run against the RELEASE build (the stapled `build/export/Talkie.app` or the
DMG-installed copy in /Applications) — never a Debug build: signing, hardened
runtime, and TCC identity differ. Re-run the FULL matrix before every tagged
release. Spec reference: design spec §11.

Build under test: Talkie ________ (version) · macOS ________ · date ________

## Insertion targets (spec §11)

Hold `fn`, say a sentence with fillers and one "scratch that" correction,
release. Pass = cleaned text lands at the cursor within ~1–2.5s and the target
app never loses focus.

- [ ] Slack — message field (casual style: contractions kept)
- [ ] Mail — compose body (polished style: complete sentences)
- [ ] Notes — note body
- [ ] Safari — a web text area (e.g. a GitHub comment box)
- [ ] Xcode — source editor; dictate "set userID to fetchUserID of session" →
      identifiers stay verbatim, plain ASCII quotes (technical style)
- [ ] Terminal — command line; output is plain ASCII, no smart quotes

## Guards

- [ ] Password-field refusal: focus a password input (Safari login form or a
      `sudo` prompt in Terminal), dictate → NOTHING inserted, notification
      "Password field" appears, History gains no completed row
- [ ] Pasteboard restore: copy the word MARKER → dictate into Notes → after
      insertion, ⌘V pastes MARKER again (user clipboard restored)
- [ ] Pasteboard race: start a dictation, copy something else while the pill
      shows "Polishing…" → after insertion, ⌘V pastes the user's newer copy
      (no restore-clobber)
- [ ] Accessibility revoked (System Settings → Privacy & Security →
      Accessibility → toggle Talkie off): dictate → text lands on the
      clipboard + "Copied — press ⌘V" notification. Re-grant afterwards.

## Cancellation & modes

- [ ] Esc during recording → pill returns to idle, nothing inserted,
      History shows a cancelled row
- [ ] Esc during "Polishing…" → same
- [ ] Hands-free: double-tap `fn` starts; releasing `fn` mid-session does NOT
      stop it; a single `fn` tap is IGNORED; a second double-tap stops and processes
- [ ] ⇧⌥V re-pastes the last dictation at the current cursor
- [ ] Sub-300ms `fn` tap → nothing recorded, no error

## Engines & offline (spec §10)

- [ ] Local mode (Settings → Engines → "On this Mac") → dictation works,
      History row shows engine "parakeet"
- [ ] Offline fallback: cloud mode + Wi-Fi OFF (models downloaded) → dictation
      still inserts, pill flashes the "offline" badge, History shows "parakeet"
- [ ] Wi-Fi OFF + local models removed (Settings → Engines → "Remove models";
      status flips to "Not downloaded") → error pill
      "No internet connection.", nothing inserted.
      Re-download models afterwards.

## Fresh-machine onboarding (spec §11)

On a NEW macOS user account (or a clean VM):

- [ ] Mount the DMG, drag Talkie to /Applications, launch → no Gatekeeper
      block ("Apple checked it for malicious software" path, no right-click
      bypass needed)
- [ ] Onboarding walks through: welcome → microphone →
      accessibility → fn-key setup (🌐 key → Do Nothing deep link works) →
      engine choice → live practice → done
- [ ] First dictation after onboarding works in TextEdit
- [ ] Select “Start dictating”, quit, relaunch, then restart/login → onboarding
      never reopens
- [ ] Close onboarding before Done → it reopens on the next launch
- [ ] Upgrade a configured legacy install → setup migrates to completed and
      onboarding does not appear
- [ ] Run Setup Assistant manually after completion → completion remains set

## Permission recovery

- [ ] Revoke Microphone after setup and relaunch → no onboarding or focus steal;
      one notification links directly to Microphone settings and Settings shows red
- [ ] Revoke Accessibility after setup and relaunch → no onboarding or focus steal;
      delivery uses clipboard and repair links target Accessibility settings

## Realtime and focus switching

- [ ] Instant mode: switch away during speech, return to the original app just
      before releasing `fn` → the complete result lands once in the original app
- [ ] Remain in a different app on release → no keystroke lands there; complete
      text is copied to clipboard
- [ ] Repeat with delayed speech immediately before release and with two VAD
      pauses → no missing, duplicated, or reordered segment

## Productivity and privacy

- [ ] Snippet triggers match whole phrases case-insensitively and preserve the
      expansion byte-for-byte through cleanup
- [ ] “new line” and “new paragraph” produce the expected layout
- [ ] “press enter” is inert by default; when opted in it works only as a suffix
      while the press-time target remains focused
- [ ] Switch language from the menu bar for one session; regional formatting is
      honored and local mode clearly reports its English-only model limit
- [ ] Enable context awareness → spacing/capitalization fits cursor context;
      disable it or exclude the app → no field text is read
- [ ] Password/secure fields never provide context; surrounding/selected text is
      absent from History, JSONL reports, Console logs, and transcription requests
- [ ] Change or disconnect the selected microphone → Talkie falls back cleanly
      and surfaces the active device
- [ ] Selection transform preview shows original/result/diff; apply, retry, and
      undo work without persisting the selected text

## Signed host matrix

- [ ] Automated signed checks pass in TextEdit, Notes, and Terminal using fixture
      audio/provider responses with the real focus and insertion stack
- [ ] Assisted checks pass in Slack, Mail, Safari, and Xcode
- [ ] Secure-field, physical `fn`, real microphone, launch-at-login, offline mode,
      Gatekeeper, clean-user install, signature seal, and update identity pass

## Native pill and icon

- [ ] Switch the real Appearance picker through Ink Line, Calm Flow Ribbon, and
      Bare Wave; each is chromeless and clearly distinct while dictating
- [ ] Real microphone energy produces a smooth response without jitter; silence
      settles instead of continuing to fabricate activity
- [ ] Each organic style stays legible over light and dark desktops, with no
      capsule, glass, notch, or background surface
- [ ] Reduce Motion removes repeating scale/pulse motion while state changes and
      cancellation remain immediate; Increase Contrast keeps the outline readable
- [ ] Physical `fn` push-to-talk and hands-free transitions show recording,
      processing, success, error, offline, and raw-fallback states correctly
- [ ] The non-activating production pill stays positioned correctly on multiple
      displays, Spaces, top/bottom placements, and after display-scale changes
- [ ] Native Depth icon is crisp at small, medium, and large Dock sizes and is
      recognizable in Finder, Spotlight, Launchpad, and the app switcher
- [ ] Icon transparency, rounded margin, shadow, glass capsule, and five waveform
      bars are not clipped in either light or dark macOS appearance

## Updates

- [ ] Updates are manual: download the new zip, replace `Talkie.app`. After an
      ad-hoc update, re-grant Accessibility if dictation only copies to clipboard
      (see docs/install-free.md).

Result: PASS / FAIL — blockers filed: ____________________
