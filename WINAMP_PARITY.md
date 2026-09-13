# Winamp parity plan (research: Winamp SA.cpp, Webamp port, WACUP defaults)

## Reference facts
- Classic analyzer: 76 measurements @150Hz → grouped by 4 → 19 bars,
  75 columns (3px + 1 gap), 16 rows, 76fps.
- Bars: instant rise, FIXED linear fall (~0.5/frame).
- Peaks: hang, then accelerate downward (drop speed ×1.05/frame from 3/256).
- WACUP defaults: 3px bands, 1px gaps, 2px segments, fire scheme, peak fade.
- Modern skins: dense thin bars, dotted backdrop, reflection, fire palette.

## Status
- ✅ Phase 1 (feel): event-driven preview (direct `hostWidget.spectrumBands`
  binding, 33ms timer deleted); Winamp peak physics (hang + ×1.05
  accelerating fall, falloff→initial speed) in shared VisualCanvas.
- ✅ Phase 2 (motion): `--fall-mode linear` (instant rise, fixed 0.05/frame
  fall) behind the Linear-fall toggle (engine restart on flip); `--fft-size`
  256..8192 validated (default 2048; 1024 verified sane, bass tradeoff kept
  as experiment, not default).
- ✅ Phase 3 (look): dotted backdrop (default on), floor reflection toggle,
  true oscilloscope (`--wave` 128-pt feed, own protocol line, canvas plots
  real data with synth fallback) behind the Oscilloscope toggle.
- ⬜ GPU fallback: only if Canvas CPU regresses (GL spare lacks all v7.7+
  features; still CPU-packs per frame).
