# omaviz — Issue List

> Goal (2026-09-13): **Winamp spectrum-analyzer quality** on all surfaces.
> Fix in queue order. Each fix is verified visually with computer-use
> (toggle the option, screenshot mini/preview/desktop, compare motion +
> shape + color). Options may change along the way; quality + performance
> rule every decision.

## Fix queue (in order)

### #13 ~~[perf] Engine emits duplicate 60Hz frames~~ ✅ Fixed
Fresh-chunk + silence-aware emit with 5Hz heartbeat. Verified: 47/s live
with music (`silent=False`, no starvation); steady silence/idle → 5Hz.
34 cargo tests green.

### #23 ~~[perf] Preview repaints ~30/s unconditionally~~ ✅ Fixed
Frame sequence counter (`spectrumData.seq`); preview pushes only new frames.

### #3 ~~[perf] Desktop CPU usage~~ ✅ Improved (36% → 20.5%)
With music playing, desktop open: shell 7.4%, desktop 20.5%, engines
0.5%/0.6%. No throttle added — revisit only if it regresses.

### #12 ~~[reliability] Frozen bars when PipeWire capture dies~~ ✅ Fixed
Chunk arrivals timestamped; 2s gap drops the stale frame and emits
explicit zero-silence at heartbeat rate. 34 cargo tests green; mini
verified live on the new binary.

### #14 ~~[robustness] `--bands` CLI value unvalidated~~ ✅ Fixed
Clamp 4..=512 with clear error. Verified: 0 and 600 rejected, 128 runs.
NaN-JSON path unreachable. 34 tests green; mini live on new binary.

### #22 ~~[quality] `[mini] gap` config doesn't change rendered spacing~~ ✅ Fixed
All three surfaces bind rendered `gapPx` to config (clamped 0..6).
Verified: gap=3 shows clear spacing, restored to 1.

### #21 ~~[reliability] Engine retry gives up after 10 tries~~ ✅ Fixed
Indefinite backoff retry (1.5s → 30s cap, reset on frames). Verified:
killed engine → new pid in <5s → mini live, no errors.

### #15 ~~[maint] Dead pause machinery~~ ✅ Fixed
Removed `paused`/`detachedRunning`/`isPaused` + unreferenced `plugin/Model/`
(Config/Spectrum/Visuals duplicates). `detachProc` kept as the desktop
spawner. Mini verified live after removal.

### #16 ~~[reliability] Two FileViews whole-file-write the same config~~ ✅ Fixed
All writers now base on frequently-polled views (bar: 500ms configFile,
desktop: 100ms cfgWrite) instead of write-only caches — staleness bounded,
no async load-then-write chaining needed for click-rate writes.

### #2 ~~[quality] Theme changes propagate~~ ✅ Fixed
Bars follow the **live** shell accent when `color_sync=true`
(`Color.accent` + darker variant, reactive to theme switches); otherwise
config `theme_bottom/top`. No config round-trip needed.

### #8 ~~[quality] Theme-aware backgrounds~~ ✅ Fixed (bar/panel; desktop static)
Mini container uses `Color.background` (identical on dark theme, correct
on light). Desktop window stays static `#0c0c12`: standalone
`quickshell -p` cannot resolve `qs.*` imports (shell-context only) — the
import killed the window on launch, caught 2026-09-13. Border unchanged.

### #6 ~~[quality] Per-surface band counts~~ ✅ Verified
Bar-feed 128 (mini→32 max-downsample, preview→64), desktop 256 (dense
spikes near 1:1). All three verified visually; no setting needed.

### #24 ~~[coherence] colorSync palettes ignore theme colors~~ ✅ Fixed
`fillFor` hardcoded blue/purple/orange ramps deleted. Canvas takes
`themeBottom`/`themeTop` props bound from config on all surfaces:
colorSync=false → bottom-to-white-hot, true → bottom-to-top theme blend.
Mini verified live in amber after rewrite.

### Small batch (one pass) — ✅ Fixed
- #17 build.sh no longer hard-fails without `qsb` (warn-only; GL unused)
- #20 `source` JSON-escaped in frame.rs + round-trip test (35 green)
- #10 engine fallback: covered by #21 retry + #12 stale-silence (dimmed state still open if wanted)
- #11 VisualCanvasGL.qml: kept as documented spare (zero runtime cost)
- #18 version + spec drift fixed (manifest 7.8.0, spec v7.8.0 documents shared Canvas, options, flag/heartbeat, emit policy)
- #19 empty plugin/tests/ removed; QML covered by qmllint, engine by cargo test (35 green)
- #7 multi-channel: deferred by design (needs protocol + UI; not quality-blocking)

---

## Fixed archive

- #1 Settings toggles ✅ v7.7 — `writeVizOption(s)` + Toggle/PanelSlider
- #4 Desktop toggle ✅ v7.6.2/v7.6.3 — double-click, shared flag + heartbeat lease, launcher + keybinds fixed
- #5 Settings options ✅ v7.7 — Peaks + fall slider, Spikes (dense gapless, Fire-coupled), Fire (shared vertical gradient), Stacks (preview/desktop)
- #9 Mini peaks ✅ v7.7 — mini on shared VisualCanvas; all surfaces honor Peaks

---

## Summary

| State | Count |
|-------|-------|
| Queued | 14 + small batch (7) |
| Fixed | 4 |
