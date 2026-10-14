# Strings motion plan from the Plexamp recording

Status: planned, not part of the current review-fix install.
Reference: user video `ScreenRecording_10-12-2026 11-47-33_1.mp4`, 9.38 seconds,
1180×2556, 60 fps. Inspected full-screen context, half-second samples through the
clip, and 0.1-second samples around 2–2.8 seconds. Colors are artwork-dependent;
match motion and depth before judging the palette.

## Observed

- Many fine strands span the full width and continue beyond the edges; there is
  no center-pinched almond envelope or anchored endpoint.
- Tight waves coexist with a few very broad, softly blurred curves in front.
  Fine strands remain separable; the broad curves do not obscure all detail.
- The bundle contracts and expands substantially around a stable horizontal
  centerline. Individual strands have different heights and prominence.
- Changing phase relationships produce sliding crossings and a rotating/twisting
  tube impression. The broad curves move on a different apparent timescale.
- Several strands look sharp while others look defocused. The recording alone
  does not prove whether blur changes with depth during each rotation.
- The clip contains playback throughout; it does not establish silence behavior.
  Exact FFT mapping, phase speeds, and attack/release constants are unknown.

## Current differences

`renderer/stringsnode.cpp` assigns fixed layer-based angular velocities and static
blur/opacity categories. `renderer/shaders/strings.vert` applies `tanh` to the
complete vertical displacement, compressing large arcs toward similar limits.
The 224-sample cap also deserves review for the highest-frequency curves at
large sizes. Current shared RMS metadata fixes a real loudness blind spot but
is not a complete motion redesign.

## Proposed implementation order

1. **Radius response:** keep a uniform radius along each strand's length. Drive
   global radius from full-window RMS and individual radii from the existing 16
   spectral envelopes. Apply a soft knee to the radius control, rather than
   flattening each curve's vertical coordinates. Reserve headroom for accents.
2. **Independent motion:** retain integrated phase per strand, with separate slow
   foreground and faster fine-strand groups. Add bounded, smoothly filtered
   audio modulation; avoid phase jumps when loudness or sensitivity changes.
   Keep rotation separate from waveform ripple and radial expansion.
3. **Depth:** compute a consistent depth coordinate alongside each projected
   curve. Tune thickness, opacity, and feathering from depth, preserving a few
   broad foreground strands. Compare against static blur first: depth-dependent
   blur is an implementation hypothesis, not a fact recovered from the video.
4. **Sampling:** choose mesh resolution from curvature/frequency and device scale,
   with a measured upper bound. Keep the retained GPU path and a shared CPU
   reference. Do not add a second implementation for the mini.
5. **Artwork palette:** expose Artwork for Strings and bind extracted cover hues
   without changing the existing Original/Custom choices. Treat any blurred
   artwork backdrop as a separate option; motion must work on transparency too.

## Acceptance evidence

- Replay the same reference audio into omaviz; compare equal-aspect crops at
  matched timestamps. Confirm expanded and contracted passages, broad/fine
  motion separation, stable centerline, and no clipped or flattened peaks.
- Inspect a bounded native sequence at normal, wide, tall, and mini dimensions,
  plus fractional scaling. Ensure fine curves remain smooth and distinguishable.
- Test silence, impulse, steady low/high tones, sensitivity limits, mode switches,
  and 30/60/120 Hz presentation. Equal elapsed time should yield equal phase.
- Measure CPU/frame/GPU timing separately from visual similarity. Define and
  enforce the performance budget before increasing geometry or blur layers.
- Preserve shared renderer ownership, Strings transparency, no center taper,
  old-frame compatibility, and all Spectrum/Siri physics.

The review-fix install only corrects signal ingestion/loudness and settings;
it deliberately preserves the existing Strings motion until this plan is built.
