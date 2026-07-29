# OpenAI Transcription Models Integration Design

**Date:** 2026-07-29

**Status:** Approved

## Objective

Adopt OpenAI's recommended transcription models throughout Talkie:

- `gpt-transcribe` for completed recordings and bounded batch requests.
- `gpt-live-transcribe` for live microphone transcription.

The integration must expose the models' useful context, language, latency, streaming,
and detected-language behavior while keeping Talkie's local transcription and
OpenRouter paths unchanged. Existing OpenAI transcription models remain available
as labelled legacy fallbacks.

## Source contract

The implementation is based on the current official documentation:

- [Transcription overview](https://developers.openai.com/api/docs/guides/transcription)
- [File transcription](https://developers.openai.com/api/docs/guides/speech-to-text)
- [Realtime transcription](https://developers.openai.com/api/docs/guides/realtime-transcription)
- [`gpt-transcribe`](https://developers.openai.com/api/docs/models/gpt-transcribe)
- [`gpt-live-transcribe`](https://developers.openai.com/api/docs/models/gpt-live-transcribe)
- [Pricing](https://developers.openai.com/api/docs/pricing)

The relevant contract is:

- `gpt-transcribe` uses `/v1/audio/transcriptions`, costs an estimated
  `$0.0045/minute`, returns text plus reliably detected languages, and can stream a
  completed file as `transcript.text.delta` and `transcript.text.done` SSE events.
- `gpt-live-transcribe` uses a Realtime transcription session, costs
  `$0.017/minute`, emits deltas and completed events correlated by `item_id`, and
  supports `minimal`, `low`, `medium`, `high`, and `xhigh` delay values.
- Both new models support `prompt`, `keywords`, and plural `languages`.
- New models must not receive the legacy singular `language` field.
- Legacy OpenAI transcription models continue to receive the fields they already
  support.
- Keywords containing `<`, `>`, CR, or LF are rejected by the API. Talkie will
  normalize CR/LF to spaces, reject angle-bracket keywords at dictionary-entry
  validation, and defensively omit invalid legacy entries from requests.

## Product behavior

### Defaults and compatibility

- Fresh installations default batch transcription to `gpt-transcribe`.
- Fresh installations default instant transcription to `gpt-live-transcribe`.
- Existing persisted model choices are not silently overwritten.
- Built-in profiles adopt the new defaults.
- `gpt-4o-transcribe`, `gpt-4o-mini-transcribe`, and
  `gpt-realtime-whisper` remain selectable under a Legacy label.
- OpenRouter model selection and local FluidAudio/Parakeet behavior do not change.

### Transcription context

Talkie builds one privacy-safe `TranscriptionContext` per dictation:

- `prompt`: an optional, user-authored description of the recording context.
- `keywords`: dictionary prompt terms, normalized and de-duplicated.
- `languages`: the expected spoken languages selected by the user.

Focused-field text, selected text, clipboard contents, transcript history, and
credentials are never placed in transcription context. Context awareness continues
to apply only to the cleanup provider.

For the new models, batch multipart requests use repeated `keywords[]` and
`languages[]` fields, and Realtime session updates use JSON arrays. For legacy
models, Talkie preserves its existing vocabulary prompt and singular language hint.

### Language settings

The existing `pinnedLanguage` remains the cleanup/output-language preference.
Talkie adds `expectedInputLanguages: [String]` for ASR hints:

- An empty array means automatic language detection.
- Existing installations without the new key seed the array from
  `pinnedLanguage` when possible.
- New-model requests may send multiple ISO 639-1 codes and supported Chinese
  regional codes.
- Regional display values are mapped to provider-supported codes before sending.
- Unsupported values are not sent.

`gpt-transcribe` detected languages are retained on `Transcript`, stored separately
from the configured output language, and shown in History. Live transcription does
not claim detected-language output because the model does not return it.

### Realtime behavior

Instant mode uses `gpt-live-transcribe` with `medium` delay by default. Advanced
Settings exposes all five documented delay levels with plain-language descriptions.
The existing server VAD, manual final commit, `item_id` ordering, bounded settling,
hard timeout, and batch fallback remain in place.

Talkie also accepts `gpt-transcribe` as an advanced Realtime choice for its
documented committed-turn workflow. It is labelled as a specialized,
accuracy-oriented option rather than the live default.

### Completed-file streaming

When batch streaming is enabled, `gpt-transcribe` sends `stream=true` and consumes
SSE events:

- `transcript.text.delta` updates the pill preview only.
- `transcript.text.done` supplies the authoritative final text and detected
  languages.
- Cleanup and insertion still wait for the final event.
- A malformed or disconnected SSE stream fails through the existing retry/error
  path; it does not insert an incomplete transcript.

Legacy batch models keep the current non-streaming JSON request. OpenRouter and
local engines are unaffected.

## Data and UI changes

New persisted settings:

- `realtimeTranscriptionModel`, default `gpt-live-transcribe`.
- `realtimeTranscriptionDelay`, default `medium`.
- `transcriptionContextPrompt`, default empty.
- `expectedInputLanguages`, default empty or migrated from `pinnedLanguage`.
- `streamBatchTranscription`, default `true`.

Advanced Settings gains:

- Separate OpenAI Batch and Instant model pickers.
- A Realtime delay picker.
- An expected spoken languages multi-select control.
- A recording-context text field.
- A batch progress toggle.
- Model descriptions, current per-minute estimates, and Legacy labels.

Simple Settings stays profile-oriented. It shows the chosen profile's batch/live
model summary and keeps the simple language control understandable without exposing
transport details.

## Diagnostics and privacy

Structured diagnostics may record model ID, delay level, number of keywords,
number of language hints, event type, duration, and failure category. They must not
record prompt text, keyword text, transcript text, surrounding context, credentials,
audio, or clipboard contents.

## Verification

Routine CI remains deterministic and credential-free. It validates:

- capability-aware request fields;
- defaults and migrations;
- batch JSON and SSE parsing;
- Realtime session JSON and event ordering;
- detected-language persistence;
- cost calculations;
- profile and Settings behavior;
- privacy-safe diagnostics.

The opt-in live verifier sends a short non-sensitive fixture through
`gpt-transcribe` in JSON and SSE modes and performs a short WebSocket session with
`gpt-live-transcribe`. Live verification requires `OPENAI_API_KEY` and remains
outside routine CI.

## Explicit non-goals

- Speaker diarization, timestamps, subtitle formats, and English translation remain
  specialized legacy-model workflows and are not part of Talkie's dictation UX.
- Talkie will not send focused-field context to a transcription provider.
- This work does not replace OpenRouter or FluidAudio.
- This work does not add account sync, cloud history, or team features.
