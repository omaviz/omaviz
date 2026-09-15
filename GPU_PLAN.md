# GPU visualization plan (no implementation — decision: STAY on Canvas-2D)

## Current measured baseline (v7.10, 2026-09-13)
- Mini (in-shell): ~7% of one core (15fps throttled), shares the 350MB
  quickshell process — omaviz's own textures are a few hundred KB.
- Desktop window: ~20% of one core (60fps Canvas-2D, 256 bands).
- Engine (x2 feeds): 0.5% CPU, ~9MB RSS each. Negligible.
- End-to-end latency: 60Hz chunked pipe → paint, no perceptible lag
  (user-confirmed "happy with responsiveness").

## What GPU would buy
- Desktop ~20% → ~6-8% CPU (JS peak-tracking + QML plumbing remains;
  only the raster moves to GPU), plus small GPU load.
- Memory: +2-4MB texture/shader overhead. No meaningful win.
- Mini: no win at all (already throttled, dominated by bar IPC).

## What GPU would cost
- Full parity re-implementation in WGSL: spikes tips, splits segments,
  fire gradient, dots, reflection, scope trace, mono, peak physics —
  every feature must be rebuilt and re-verified pixel-for-pixel.
- qsb toolchain back in the build (warn-only today for a reason).
- Per-GPU-driver testing (AMD here; no second machine to verify on).
- Two renderers to keep in sync forever, or a flag-day rewrite.

## Decision
STAY on the single Canvas-2D renderer. GPU saves ~12% of one core on
the desktop window only, at the cost of a second renderer and a
perpetual parity tax. Revisit only if: desktop CPU exceeds 40% on the
user's hardware, or a 120Hz+ target is set. Dead GL spare
(VisualCanvasGL.qml, glspectrum.js, shaders/) was removed in v7.11.
