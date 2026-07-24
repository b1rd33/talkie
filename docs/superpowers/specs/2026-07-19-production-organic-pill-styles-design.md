# Production Organic Pill Styles Design

## Goal

Promote the three selected native waveform concepts into real Talkie pill styles and remove the Debug Pill Lab completely.

## Production Styles

Add three persisted `PillStyle` cases to the existing Pill Style selector:

- `Ink Line`: one fine organic trace with a tapered speech envelope.
- `Calm Flow Ribbon`: three coordinated, slow-moving traces with one dominant center line.
- `Bare Wave`: one continuous organic waveform with slightly fuller amplitude than Ink Line.

Each style uses Talkie's real `AudioLevelReading` source during production dictation. Audio energy is temporally smoothed so speech produces fluid movement rather than abrupt mechanical jumps.

## Visual and State Behavior

- The three styles render directly over the desktop with no capsule, glass, notch, or colored background.
- They remain predominantly monochrome and inherit increased-contrast behavior.
- Reduced Motion freezes decorative phase drift while preserving meaningful audio-level response.
- Recording and hands-free states show the live waveform; hands-free retains an unobtrusive lock cue.
- Transcribing, cleaning, and inserting use slower or faster phase behavior to communicate progress without adding text-heavy chrome.
- Success and error use small semantic endpoint markers only.
- Existing placement settings and panel sizing remain compatible.
- Existing Frosted Glass, Dynamic Island, Calm Wave, and Hidden Idle styles keep their current behavior.

## Settings and Persistence

- Add the three names to the existing Pill Style dropdown in Settings.
- Persist them through the same `pillStyle` defaults key and raw-value decoding used by current styles.
- Existing users keep their selected style; unknown values continue to fall back safely.

## Debug Lab Removal

Delete the Pill Lab implementation, `--pill-lab` launch handling, Debug window controller, microphone-preview adapter, Space monitor, lab-only model/renderers, lab UI tests, rendering/model tests, Release-isolation script, and lab-specific manual test documentation.

Keep general app-icon studies and unrelated production tests. Remove all Pill Lab design and implementation-plan documents; this production specification becomes the single source of truth for the promoted styles.

## Architecture

- Move reusable organic signal math and production renderers into `Talkie/UI/FlowBar` without `#if DEBUG`.
- Route the new `PillStyle` cases from `PillRendererView` to the new transparent renderer.
- Keep waveform shaping separate from the renderer as a deterministic value type so smoothing and reduced-motion behavior are unit-testable.
- Do not add transcription, network, provider, or recording-file behavior.

## Testing

- Add unit tests for new raw values, labels, persisted round trips, smoothing, reduced motion, and state rendering.
- Render each new production style offscreen and confirm nonempty output with transparent corners.
- Update Settings UI automation to confirm all three dropdown entries.
- Run all signed logic and UI suites.
- Manually dictate with each style using the real microphone and verify recording, processing, success, hands-free, and silence decay.
- Build Release and verify no Pill Lab symbols or `--pill-lab` entry point remain.

## Out of Scope

- Bare Wave sub-variations, a second style selector, notch concepts, Debug preview tooling, transcription changes, and changes to existing styles.
