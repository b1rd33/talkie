# Minimal Pill Feedback Design

## Goal

Make Talkie's production pill quieter and more direct:

1. Show the live waveform while recording.
2. On release, compress and crossfade the waveform into a thin neutral ring.
3. Keep the ring subtly alive while transcription, cleanup, and insertion run.
4. Shrink and fade the ring as soon as insertion succeeds.

The pill must not show processing text or a success checkmark.

## User Controls

Add two independent settings under pill appearance:

- **Show recording timer**, off by default.
- **Show cancel button**, off by default.

These controls apply to every visible pill style. Existing users receive the new
minimal defaults unless they explicitly enable either control.

Hiding the cancel button changes presentation only. Escape and the configured
dictation controls continue to cancel normally.

## Visual States

### Recording

- Render the selected style's live waveform.
- Render the timer only when `showPillTimer` is enabled.
- Render the cancel button only when `showPillCancelButton` is enabled.

### Processing

Transcribing, cleaning, and inserting share one visual state.

- Render a thin neutral ring with no text.
- Render the cancel button only when `showPillCancelButton` is enabled.
- Do not restart the transition when the internal processing state changes.
- Use a subtle opacity/scale breath that does not resemble a progress estimate.

### Completion

- Do not render a checkmark or success badge.
- Transition directly from the processing ring to the pill's hidden or idle
  presentation.
- For styles that are hidden outside active dictation, shrink and fade the ring
  before ordering the panel out.

### Errors and Warnings

- Preserve the existing readable error presentation.
- Preserve the RAW cleanup-failure warning because it reports degraded output.
- Preserve the offline indicator.

## Motion

Normal motion:

- Recording-to-processing: 180–220 ms ease-out crossfade and scale.
- Processing breath: low-amplitude, approximately 1.4–1.8 seconds per cycle.
- Completion: 140–180 ms ease-in shrink and fade.

Reduced Motion:

- No breathing or scale animation.
- Use a short opacity crossfade only.

The implementation must animate transform and opacity rather than layout size.

## Architecture

Persist `showPillTimer` and `showPillCancelButton` in `SettingsStore`. Pass them
through `PillPresentation`, keeping the renderer independent of settings storage.

The renderer owns the native SwiftUI ring and transition. Internal dictation
states remain unchanged; transcription, cleanup, cancellation, history, and text
delivery logic are not modified.

Remove the delayed processing-label state and success-checkmark state from
`FlowBarView`. The completion timestamp remains available for visibility timing,
but the brief post-completion panel lifetime is shortened to the ring's exit
duration.

## Accessibility

- VoiceOver continues to announce the real internal state.
- The cancel accessibility action remains available while processing, even when
  the visible X is disabled.
- Settings switches use explicit labels and help text.
- Reduced Motion is honored.

## Tests

Add regression coverage for:

- New settings default to false and persist.
- Timer and cancel visibility are represented independently.
- Processing states expose no visual label and use the shared ring phase.
- Success does not map to a checkmark presentation.
- The minimal native renderer produces the same recording image regardless of
  elapsed time when the timer is disabled.
- Reduced Motion disables the ring's breathing geometry.
- Existing dictation, cancellation, error, and accessibility tests continue to
  pass.

## Acceptance Criteria

- Default recording pill contains only the waveform and required status badges.
- Releasing dictation transforms the waveform into a thin neutral ring.
- No `Processing…`, `Transcribing…`, `Cleaning…`, or `Inserting…` text appears.
- No success checkmark appears.
- Timer and visible X can be enabled independently in Settings.
- Escape cancellation continues to work with the visible X disabled.
- The full automated suite passes and the rebuilt app is restarted for testing.
