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
      stop it; a single `fn` tap (or second double-tap) stops and processes
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

## Licensing & trial (spec §9)

- [ ] Trial expiry: remove the license key
      (`security delete-generic-password -s com.archiev.talkie.license -a license_key`)
      but KEEP the sealed trial (start one via onboarding if none exists),
      then System Settings → Date & Time → disable auto and set the clock
      >14 days AHEAD of the sealed start → dictation gated with the "trial
      expired" pill state; Hub/History/Settings still open. Restore the
      clock afterwards.
- [ ] Entering a valid license key unlocks dictation immediately
- [ ] Clock rollback (set system clock before the sealed trial start) →
      treated as expired

## Fresh-machine onboarding (spec §11)

On a NEW macOS user account (or a clean VM):

- [ ] Mount the DMG, drag Talkie to /Applications, launch → no Gatekeeper
      block ("Apple checked it for malicious software" path, no right-click
      bypass needed)
- [ ] Onboarding walks through: welcome → trial/license → microphone →
      accessibility → fn-key setup (🌐 key → Do Nothing deep link works) →
      engine choice → live practice → done
- [ ] First dictation after onboarding works in TextEdit

## Updates

- [ ] Updates are manual: download the new zip, replace `Talkie.app`. After an
      ad-hoc update, re-grant Accessibility if dictation only copies to clipboard
      (see docs/install-free.md).

Result: PASS / FAIL — blockers filed: ____________________
