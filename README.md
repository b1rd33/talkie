# Talkie

A menu-bar push-to-talk dictation app for macOS. Hold **fn**, speak, release —
your words are transcribed, polished, and dropped into whatever app you're in.

- **Three engines:** cloud batch, cloud *instant streaming*, or fully on-device.
- **Live preview & live typing:** in instant mode, watch your words stream into
  the pill — or type them straight into your document as you speak.
- **Cleanup that fits the moment:** punctuation-only up to full rewrite, or skip
  it entirely for raw, instant text.
- **A pill that gets out of the way:** chromeless waveform, Dynamic-Island, or
  frosted glass — follows your system light/dark appearance.

> Requires macOS 14+. Talkie lives in the menu bar (no Dock icon by default).

## Install

Download the latest `Talkie-x.y.z-adhoc.zip` from
[Releases](../../releases), unzip, and drag `Talkie.app` to `Applications`.

The free build isn't notarized, so the first launch needs a one-time
**System Settings → Privacy & Security → Open Anyway**. Full steps (and the
microphone / Accessibility grants) are in **[docs/install-free.md](docs/install-free.md)**.

## Setup

On first run, paste an API key in onboarding (or **Settings → Engines → API Keys**):

| Key | Used for |
|-----|----------|
| **OpenRouter** | transcription (batch) and cleanup — the simplest single key |
| **OpenAI** | *instant streaming* (OpenAI's realtime API) and, optionally, direct cleanup |

On-device transcription needs no key — download the local models from
**Settings → Engines → Local models** (~2 GB).

## Usage

- **Hold `fn`** to dictate; release to insert.
- **Double-tap `fn`** for hands-free (toggle on/off).
- **`⇧⌥V`** pastes your last dictation again.
- Pick the engine from the menu-bar dropdown or **Settings → Engines**.

### Engine modes

| Mode | What it does | Cost |
|------|--------------|------|
| **Cloud — batch** | Uploads the recording after you release (gpt-4o transcribe). | ~$0.18/hr |
| **Cloud — instant streaming** | Streams audio while you speak (gpt-realtime-whisper); text lands ~1s after release. Enables the live preview + live typing. | ~$1.02/hr |
| **On this Mac** | Runs locally (Parakeet), offline and free. | free |

### Instant mode extras

- **Live preview** — the pill shows your words as they stream in.
- **Skip cleanup (fastest)** — insert the raw streamed text with no polish pass.
- **Type live into the app** — words appear in your document as you speak
  (requires Accessibility; implies skip-cleanup since already-typed text can't be
  re-polished).

### Cleanup levels

`None` (raw) · `Light` (punctuation) · `Medium` (also remove fillers) ·
`High` (also self-corrections & lists) · `Custom` (your own instructions).
Runs via OpenRouter or OpenAI — **Settings → Engines → Cleanup**.

## Privacy

- Audio is **deleted after transcription** by default (opt in to keep recordings).
- Talkie is **not sandboxed** — it needs Accessibility to type into other apps,
  and it refuses to type into secure/password fields.
- Keys live in the macOS Keychain.

## Build from source

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project Talkie.xcodeproj -scheme Talkie -configuration Debug build
xcodebuild test -project Talkie.xcodeproj -scheme Talkie -destination 'platform=macOS'
```

## Releasing

`scripts/build-release-adhoc.sh` produces an ad-hoc-signed zip to attach to a
GitHub Release. Updates are manual (download the new zip) — see
[docs/install-free.md](docs/install-free.md).

## Tech

SwiftUI + AppKit, [XcodeGen](https://github.com/yonaskolb/XcodeGen) project,
[FluidAudio](https://github.com/FluidInference/FluidAudio) (local ASR),
[HotKey](https://github.com/soffes/HotKey). Test-driven; run the suite before sending a PR.
