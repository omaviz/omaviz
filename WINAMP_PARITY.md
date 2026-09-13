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
- ⬜ Phase 2 (motion): linear bar-fall engine mode behind config; FFT-1024
  latency experiment (43ms → 21ms floor, bass tradeoff).
- ⬜ Phase 3 (look): dotted backdrop + reflection toggles, oscilloscope parity.
- ⬜ GPU fallback: only if Canvas CPU regresses (GL spare lacks all v7.7+
  features; still CPU-packs per frame).
