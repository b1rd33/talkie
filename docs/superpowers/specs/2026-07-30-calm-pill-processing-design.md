# Calm Pill Processing Design

## Purpose

Make Talkie's native Swift pill feel quieter and faster after dictation without
changing transcription, cleanup, insertion, cancellation, or fallback behavior.
The pill should communicate that work continues, but it should not expose every
short-lived internal pipeline stage as a separate visual event.

## Confirmed direction

Talkie is a focused macOS dictation utility used while attention remains in
another application. Its pill should feel calm, restrained, organic, and
primarily monochrome. Color is reserved for failure and the brief success
acknowledgment. The existing waveform concepts remain unchanged.

## Recording

- Remove the yellow `bolt.fill` Instant-mode badge.
- Keep the native waveform, timer, and cancel control.
- Keep the current hands-free breathing motion and reduced-motion behavior.
- Do not replace the badge with another decorative mode indicator.

## Processing

- Preserve the internal coordinator states: `transcribing`, `cleaning`, and
  `inserting`.
- Map all three states to one visual phase named `processing`.
- Render one neutral progress indicator for the entire phase.
- Do not re-run the entry animation when the internal state advances.
- Hide processing text for the first 650 ms so fast dictations do not flash
  technical labels.
- If processing lasts at least 650 ms, reveal the single label `Processing…`.
- Keep the cancel control available throughout processing.
- Preserve specific VoiceOver labels for Transcribing, Cleaning, and Inserting;
  visual simplification must not reduce accessible state information.

## Success

- Keep the checkmark, because it confirms that insertion finished.
- Shorten its visible duration from 800 ms to 400 ms.
- Keep the containing panel alive for 600 ms after completion instead of roughly
  1.1 seconds.
- Use a 180 ms ease-out transition instead of a spring for visual phase changes.
- Reduced Motion continues to avoid waveform geometry motion and scale changes.

## Cleanup and cancellation semantics

- Releasing the dictation key still starts transcription and, when configured,
  cleanup.
- Hiding or simplifying the pill does not skip cleanup.
- The pill's cancel button continues to cancel during transcription or cleanup.
- Cleanup is skipped only by the existing cleanup settings and successful
  Instant-mode skip logic.

## Realtime fallback diagnostics

- Emit a typed event when a realtime session cannot begin and batch mode is used.
- Emit a second typed event when realtime finalization fails and batch mode is
  used.
- Production diagnostics use `Logger` and record only the fixed event name.
- Never record transcript text, provider error text, audio, context, credentials,
  clipboard contents, or selected text.
- Tests inject a capture closure and assert the correct event category.

## Testing

- Unit-test the unified visual phase mapping.
- Unit-test that visual processing labels are unified and threshold-controlled.
- Unit-test the 400 ms success and 650 ms label timing values.
- Unit-test both realtime fallback diagnostic categories.
- Keep native rendering coverage for every state and style.
- Run the complete logic suite, build a fresh Debug app, reopen it, and inspect
  the native pill.

## Out of scope

- Changing provider requests, model selection, cleanup quality, or insertion.
- Removing the cancel action.
- Redesigning waveform geometry.
- Adding new pill styles or settings.
- Exposing fallback diagnostics in the user interface.
