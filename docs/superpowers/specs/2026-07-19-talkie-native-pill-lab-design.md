# Talkie Native Pill Lab and App Icon Design

## Purpose

Talkie needs a native macOS environment for designing and verifying the floating dictation pill without requiring a microphone, global hotkey, Accessibility permission, network access, or a paid provider. The same work will establish a coherent native app icon based on the selected **Pulse Pill / Native Depth** direction.

The Pill Lab is a development and release-verification tool. It is not a user-facing production feature and must not compile into Release builds.

## Product Direction

The visual system uses one recognizable motif across the Dock icon and dictation UI:

- A deep navy macOS icon tile.
- A dimensional capsule with restrained glass highlights.
- A cyan waveform with a white central voice peak.
- Calm motion that communicates activity without demanding attention.
- No text, microphone glyph, decorative shimmer, or aggressive ripple effects.

The default motion family is **Calm Flow**:

- **Soft Settle** controls entry and exit.
- **Floating Wave** animates during ordinary push-to-talk recording.
- **Breathe** differentiates hands-free recording.
- **Minimal Motion** replaces scale and spring effects when Reduce Motion is enabled.

Motion never delays transcription, insertion, cancellation, or window dismissal.

## Architecture

### Pill presentation model

Introduce a small, value-based `PillPresentation` model containing only information required to render the pill:

- State: idle, recording, hands-free recording, transcribing, cleaning, inserting, success, and error.
- Style: bare waveform, Dynamic Island, frosted glass, and hidden.
- Motion preset: Calm Flow or Minimal Motion.
- Elapsed recording time.
- Audio level.
- Optional error message.
- Offline and raw-cleanup warning flags.
- Reduce Motion and contrast inputs.

Production code maps `DictationCoordinator`, `AudioRecorder`, and `SettingsStore` into this presentation model. The Pill Lab creates the same model directly. `FlowBarView` renders the model and emits user intents such as cancel, hide for an hour, and hide permanently. This keeps the real and preview pills on exactly the same rendering path.

No transcript, context text, credentials, clipboard contents, or provider response enters the presentation model.

### Motion system

Add a `PillMotionProfile` that centralizes durations, springs, opacity curves, waveform smoothing, and scale limits. The production default uses Calm Flow values; Reduce Motion produces a profile with stable geometry and short opacity transitions.

The state choreography is:

1. Idle to recording: Soft Settle expands horizontally from 65% to 102.5%, then settles at 100% in roughly 350 ms.
2. Recording: Floating Wave updates from the recorder at 30 fps. The capsule remains geometrically stable.
3. Hands-free: the same waveform runs while the capsule breathes between 98.5% and 101.5% over roughly 2.4 seconds.
4. Processing: waveform amplitude settles to zero and crossfades into a spinner and phase label without changing the panel frame.
5. Success: a small checkmark uses a restrained spring, remains visible for 800 ms, then fades to idle.
6. Error: icon and one-line error crossfade in; truncation keeps the panel within its fixed frame.
7. Cancel: audio motion stops immediately and the pill performs the short Soft Settle exit.

All repeating timers stop when their owning view disappears. The waveform maintains the existing common-mode run-loop behavior required by the non-activating panel.

### Native Pill Lab window

Add a Debug-only `PillLabWindow` implemented with SwiftUI and opened through the `--pill-lab` launch argument. A Debug-only menu command may also open it during development. Neither entry point nor any lab type may compile into Release.

The separate standard window contains:

- Live native pill preview on selectable desktop backgrounds.
- State and style pickers.
- Soft Settle, Floating Wave, Breathe, and Minimal Motion previews.
- Simulated push-to-talk and hands-free controls.
- Motion speed and intensity controls bounded to safe preview ranges.
- Waveform sensitivity control.
- Light, dark, and high-contrast environment toggles.
- Reduce Motion toggle.
- Position preview for top-center, bottom-center, bottom-left, and bottom-right.
- A detachable non-activating panel using the production panel behavior.
- Reset button returning every control to the production defaults.

The lab does not persist settings and never writes production defaults. Closing and reopening it starts from known defaults.

### Deterministic waveform simulator

`SimulatedAudioLevelSource` produces a seeded sequence of speech-shaped envelopes and quiet gaps. It conforms to the same small level-source interface used by the production recorder adapter.

The simulator:

- Requires no microphone permission.
- Produces identical samples for a given seed and time step.
- Supports quiet, conversational, energetic, and silence fixtures.
- Stops its clock when the preview is not visible.

This makes animation tests repeatable while leaving real-microphone verification as an assisted release check.

### Native app icon renderer

Add a Swift/Core Graphics icon-generation tool that renders the approved Native Depth icon at 1024 points and exports every macOS AppIcon slot from one drawing recipe.

The renderer uses deterministic vector geometry for:

- Rounded navy tile and native macOS margin.
- Subtle diagonal depth gradient.
- Dimensional pill with restrained inner highlight.
- Five rounded waveform bars.
- Cyan outer bars and white central peak.
- Carefully reduced detail for 16, 32, and 64 pixel variants.

Generated PNGs replace the current AppIcon assets only after visual approval of the native preview. The existing icon files remain recoverable through Git history. The menu-bar template icon remains monochrome and is not replaced by the colored Dock artwork.

## Data and Event Flow

```text
Production coordinator/recorder/settings
                 |
                 v
       PillPresentation adapter ----+
                                     |
Pill Lab controls + simulator -------+--> FlowBarView --> native panel/window
                                                        |
                                                        +--> cancel/hide intents
```

The lab feeds presentation data only. Production side effects remain owned by the existing coordinator and app delegate.

## Accessibility and Native Behavior

- The recording pill exposes state, elapsed time, warnings, and cancel action through accessibility labels without exposing transcript text.
- Decorative waveform bars are hidden from the accessibility tree.
- Cancel remains operable without making the panel key or stealing focus.
- Reduce Motion uses opacity transitions and a non-animated waveform level indicator.
- Increased Contrast strengthens borders and foreground contrast without changing layout.
- The pill remains legible in light and dark appearance and over bright, dark, and patterned desktops.
- All styles retain stable 260 × 56 panel geometry, preventing focus or placement jitter.

## Automated Testing

### Logic tests

- Production coordinator states map to the correct `PillPresentation` values.
- Calm Flow and Minimal Motion profiles contain the intended bounded timings.
- Reduce Motion selects Minimal Motion automatically.
- The waveform simulator is deterministic, bounded, and stops when inactive.
- Dynamic Island always resolves to top-center.
- Hidden style is absent while idle and visible while active.
- Error labels truncate safely and warning combinations remain deterministic.
- Icon slot generation covers every filename in `AppIcon.appiconset/Contents.json` at the required dimensions.

### Native rendering tests

Use `NSHostingView` or SwiftUI `ImageRenderer` to render fixed-size checkpoints for every meaningful state/style combination. Compare geometry and stable pixel regions with small tolerance; animation frames use fixed simulator timestamps.

Required checkpoints:

- Idle and recording for every style.
- Hands-free Breathe at minimum, midpoint, and maximum scale.
- Each processing phase.
- Success, error, offline, and raw-cleanup warnings.
- Light, dark, increased-contrast, and Reduce Motion environments.
- 16, 32, 128, 256, 512, and 1024 pixel icon outputs.

### UI tests

- Launch using `--pill-lab` and verify the separate window appears.
- Change every state, style, motion, environment, and position control.
- Detach the native panel and confirm it remains non-activating.
- Verify Cancel returns to idle.
- Verify Reset restores production defaults.
- Verify the lab does not alter the normal Talkie defaults domain.
- Verify the lab entry point is absent from Release.

### Performance tests

- Waveform redraw remains close to 30 fps without unbounded allocations.
- Idle state has no animation clock.
- Repeatedly opening and closing the lab releases timers and tasks.
- Rapid state changes do not leave the panel stuck or produce stale success/error flashes.

## Assisted Visual Verification

Automated rendering cannot judge every aspect of perceived smoothness. Release verification therefore includes a short native review:

- Watch each Calm Flow transition in the separate Pill Lab window.
- Compare the pill over bright, dark, and patterned applications.
- Move the detachable panel across multiple displays and Spaces.
- Confirm the original typing target retains focus.
- Verify live microphone waveform response later in a quiet room.
- Verify actual `fn` push-to-talk, hands-free, cancel, and focus switching.
- Verify the Dock icon at small/medium/large Dock sizes and in Finder, Spotlight, and the app switcher.

## Release Safety

- All lab entry points and implementation files are Debug-only.
- Release configuration receives a static build check rejecting `--pill-lab`, test bridges, fake providers, and simulated audio controls.
- No production credentials or defaults are read by the lab.
- No transcript or context content is displayed or logged.
- The production pill behavior changes only through the shared presentation refactor and is protected by regression tests.

## Acceptance Criteria

- A separate native SwiftUI Pill Lab window can exercise every pill state and style without permissions, network, credentials, or microphone access.
- The preview and production pill use the same renderer and motion profiles.
- Calm Flow uses Soft Settle for entry/exit, Floating Wave for push-to-talk, and Breathe for hands-free.
- Reduce Motion provides stable geometry and short fades.
- The real non-activating panel never steals focus.
- Waveform motion does not freeze, leak, or continue while idle.
- Native rendering tests cover every state, style, accessibility environment, and icon size.
- A deterministic Swift/Core Graphics tool generates a complete macOS AppIcon set matching Native Depth.
- Pill Lab code and controls are absent from Release builds.
- Existing logic, UI, and host-integration suites continue to pass.

## Out of Scope

- Shipping a user-selectable animation marketplace or arbitrary motion editor.
- Persisting experimental Pill Lab settings.
- Replacing the monochrome menu-bar template icon with colored artwork.
- Using HTML, WebView, JavaScript, Metal, or a third-party animation framework.
- Requiring real speech or provider calls for routine animation tests.
