# omaviz — Application Specification (v8.5.2)

> **Plugin id:** `org.omaviz.visualizer`
> **Version:** 8.5.2 (spec + manifest, git tag)
> **Status:** Single-package Omarchy QML plugin. Audio analysis is bundled as
> one native binary (`bin/omaviz-engine`) shipped **inside** the plugin
> directory. No systemd service, no Unix socket, no `~/.local/bin` binaries.

This document is the **source of truth** for what ships and how it is verified.

---

## 1. Goals & Non-Goals

**Goals**
- React to system playback audio (not microphone) via the default audio sink.
- Ship as a **single plugin directory** — every dependency (QML, JS, native
  engine binary) lives under `~/.config/omarchy/plugins/org.omaviz.visualizer/`.
- **Zero-build install (Architecture A):** the engine binary is **committed**
  at `bin/omaviz-engine`. Installing the plugin is just copying the
  directory + `omarchy plugin enable` — no Rust toolchain required.
- Canvas-2D based rendering (no GL shader dependency for default path).
- Winamp-style spectrum analyzer with peak-hold markers.

**Non-Goals (v7.6.1)**
- No microphone monitoring.
- No backend switching UI (source is auto + displayed, not chosen).
- Canvas-2D paints images; Qt Quick selects GPU or software compositing automatically.

---

## 2. Architecture (v7 — single package)

```
repo root = the plugin (deployed to ~/.config/omarchy/plugins/org.omaviz.visualizer/)
├── manifest.json
├── BarWidget.qml   (spawns bin/omaviz-engine, parses its stdout)
├── Panel.qml       (settings: Peaks toggle, Peak fall speed)
├── Desktop.qml     (detached window)
├── ModelStore.js   (.pragma library: pure config / protocol helpers)
├── Physics.js      (.pragma library: shared bar/peak motion model)
├── VisualCanvas.qml  (Canvas-2D renderer)
├── bin/
│   └── omaviz-engine   (Rust: capture → FFT/DSP → JSON lines on stdout;
│                         COMMITTED artifact — see Architecture A, §2)
└── tests/*.test.cjs
```

**Data flow:**
```
default sink monitor (PipeWire)
   │  (libpipewire, STREAM_CAPTURE_SINK, autoconnect)
   ▼
bin/omaviz-engine  (capture thread → Analyzer → 60Hz frame loop)
   │  one JSON object per line on stdout:
   │  {"bands":[..32],"energy":f,"beat":f,"silent":b,"source":"pipewire"}
   ▼
Quickshell BarWidget.spectrumProc (Process)
   │  SplitParser → Store.parseSpectrumLine
   ▼
Store.spectrumData { bands, energy, beat, silent, source }
   ▼
VisualCanvas (Canvas-2D) — used by mini, preview, AND desktop
```

---

## 3. Files

| File | Purpose |
|------|---------|
| `BarWidget.qml` | Waybar mini widget. Spawns engine, renders spectrum, handles detach/attach. |
| `Panel.qml` | Settings panel. VISUALIZATIONS cards, live PREVIEW, LOOK / COLOR / MOTION groups, collapsed ADVANCED, SOURCE readout. |
| `Desktop.qml` | Detached visualization window. Same VisualCanvas renderer, larger. |
| `VisualCanvas.qml` | Canvas-2D renderer. Used by mini, preview, and desktop. |
| `ModelStore.js` | Pure TOML/defaults and protocol parsing; QML components own observable state. |
| `Physics.js` | Bar/peak motion model (instant attack, rate-limited release, peak sustain). Unit-tested. |

---

## 4. Rendering — `VisualCanvas.qml` (Canvas-2D, default)

### 4.0 Physics ownership (v8.4)

The engine emits **raw** band magnitudes at ~60 Hz — no smoothing, no
fall-mode. ALL motion lives in `Physics.js` and is applied by `VisualCanvas`,
so every surface (mini, panel preview, desktop, oscilloscope) shares one
trajectory:

| Phase | Behaviour |
| --- | --- |
| Attack | instant — the bar reaches the new target on the same frame |
| Release | rate-limited (linear or exponential) — bars FALL when audio stops, never vanish |
| Peak cap | rides above the bar, HOLDS for `peak_sustain_ms` (default 100), then falls with an accelerating speed (x1.05/frame) |

`silent` from the engine is **advisory only** (it drives the settle
optimisation); it never zeroes bars. This is what keeps faint-but-audible
passages visible.

The same renderer is used for **all three contexts** (mini, preview, desktop).
Only the container size and position change.

### Rendering parameters (set by parent)

| Property | Default | Description |
|----------|---------|-------------|
| `gapPx` | config `gap` (1) | Space between bars in pixels (0 in spikes) |
| `peaks` | `true` | Show peak-hold markers (2px white; 1px hot in spikes) |
| `peakFalloff` | `0.1` | Peak falloff speed (0=holds, 1=falls fast) |
| `peakSustainMs` | `100` | How long a cap holds at its high-water mark before falling |
| `spikes` | `false` | Dense thin gapless flame spikes (~2px, width-derived count) |
| `spikeBars` | `0` | Spike count cap (0=auto; mini passes 32) |
| `fire` | `false` | Vertical red→tip flame gradient (container-shared) |
| `stacks` | `false` | Winamp segments: 3px blocks + 1px gaps (preview/desktop; desktop doubles via stackScale) |
| `sensitivity` | `1.0` | Input gain multiplier (also scales the oscilloscope amplitude) |
| `themeBottom`/`themeTop` | amber | Theme-anchored colors; live shell accent when `colorSync` |

The bar floor is unconditional (1px) — there is no `minBarHeight` setting.

### Bar rendering

1. **Discrete mapping**: `displayBands()` maps source bands to display bars:
   - **Downsampling** (display < source): max-pooling for sharp peaks
   - **Upsampling** (display > source): linear interpolation (no lockstep banding)
2. **Fill**: theme-anchored ramp (bottom → white-hot), or bottom→top theme
   blend when `colorSync`; fire uses the shared vertical flame gradient
3. **Peaks**: horizontal ticks at each bar's peak, falling at `peakFalloff`
4. **Engine feeds**: bar 128 bands (mini→32, preview→64), desktop 256;
   engine emits on fresh audio only + 5Hz heartbeat, explicit zero-silence
   2s after capture death; `--bands` clamped 4..=512

### Container differences

| Component | Container | Bar behavior |
|-----------|-----------|--------------|
| **Mini** | 28px height, 90% centered in waybar, 4px padding | Fills 100% of container |
| **Preview** | 60px height in panel | Fills 100% of container |
| **Desktop** | `min(window_h, 300px)`, bottom-anchored | Fills 100% of container |

---

## 5. Settings Panel (redesign)

The panel is grouped **by intent**, one concept per control, on a single
scrollable screen (no slide-out OPTIONS stage):

**VISUALIZATIONS**: Two caps-text cards (SPECTRUM / OSCILLOSCOPE) — pick the
viz first. Artwork is not a viz; it lives in ADVANCED as **Artwork backdrop**.
No auto-white rule — the Color setting governs bars everywhere.

**PREVIEW**: Live visualization (same renderer, larger) + helper text below
(left-aligned, muted): single-click opens the desktop window.

**LOOK** (Spectrum only): **Geometry** chips — Bars / Spikes / Stacks, one
exclusive choice (Spikes and Stacks are mutually exclusive) · **Peaks** toggle
+ **Peak fall speed** slider (the only "drop" control) · **Reflection**.

**COLOR** (all viz): **Color mode** chips — Theme / Custom / Flame, one
exclusive choice. Flame is a colour *mode*, not a geometry toggle: it lights
the bar gradient from deep red into the custom tip without touching Geometry.
**Custom tones** From (base) / To (tip) hex fields (active under Custom and
Flame, with separate persisted tone pairs) · **Gradient direction** chips — Vertical (bottom→top, default) or
Horizontal (left→right across the field) · preset swatch row (8 gradients + a
Fire swatch that selects Flame mode). Custom base is darker and tip lighter;
Flame uses its own exact base and tip, defaulting to red → yellow.
Reflection mirror is tinted with the base colour. Theme mode follows the LIVE
Omarchy accent. Mini Mono overrides this on mini only.

**MOTION**: **Response** slider (writes `[audio] sensitivity`; scales bar
reactivity AND oscilloscope amplitude with input gain) · **Mono (mini only)**.

**OSCILLOSCOPE** (shown only for the scope viz): **Line thickness** slider.

**ADVANCED** (collapsed by default, "Show"/"Hide"): Linear fall
(renderer-side, no engine restart) · Dots (static underlay) · Artwork
backdrop · read-only compositing backend status.

All controls are live-wired via `writeVizOption` / `writeVizOptions`
(atomic multi-key) / `writeAudioOption` — disk write + instant local update.

**Retired from UI, still honored in code**: `artwork_mode`/`immersive`
migrate to spectrum + backdrop on; `min_bar_height`/`splits` are gone (bar
floor is unconditional; Stacks is the canonical key).

**SOURCE**: Read-only audio source indicator (e.g., "PipeWire · default sink")

---

## 6. Config properties (`~/.config/omaviz/config.toml`)

```toml
[audio]
sensitivity = 1.0
bands = 32

[mini]
gap = 1
width_scale = 1.5
color_sync = true

[desktop]
# Runtime active/heartbeat live separately in desktop-state.toml
enabled = true
theme_bottom = "#e68e0d"
theme_top = "#f59e0b"
theme_accent = "#f59e0b"
peaks = true
peak_falloff = 0.1
peak_sustain_ms = 100
spikes = false
stacks = false
mono = false
linear_fall = true
scope = false
scope_thickness = 2
dots = true
reflect = true
artwork = false
fire = false
fire_color_from = "#be1400"
fire_color_to = "#fde047"
bar_color_custom = false
bar_color_from = "#e68e0d"
bar_color_to = "#f59e0b"
bar_gradient_dir = "vertical"
# retired keys still READ (never written): artwork_mode, immersive, splits,
# min_bar_height
```

---

## 7. Detach / desktop window lifecycle

- **Single-click** the mini → settings panel; **single-click** the live
  preview inside the panel → detached desktop window (right-click removed)
- Mini paused-state follows shared `desktop.active` + 2s heartbeat lease
  in `desktop-state.toml` (6s expiry), separate from saved settings —
  any launch path (bar, app launcher, `SUPER+V`) converges; close from any
  path brings the mini back
- Settings writes are serialized and remain optimistic until acknowledged.
  Explicit `stacks`/`artwork` settings override legacy aliases.
- Desktop self-claims the flag on open; `onClosing` clears it with a flush
  delay then `Qt.quit()` (no zombie windowless processes)
- Desktop window is 600×200; the visualization container is bottom-anchored
  and fills `max(100px, 95% of window height)`
- No title bar: 68px hover tray fades in on mouse-over (48px artwork
  thumbnail or same-size fallback, larger monospace track/artist/theme
  source lines) with a steady 16px × close button; fades out ~200ms
  after the cursor leaves

---

## 8. Operational notes

- Install: `./install.sh` (zero-build by default, uses committed binary)
- Rebuild engine: `./install.sh --build`
- Uninstall: `./uninstall.sh`
- No systemd, no socket, no `~/.local/bin`

---

## 9. Repository structure

```
omaviz/  (repo root IS the plugin — manifest.json lives here)
├── manifest.json, BarWidget.qml, Panel.qml, Desktop.qml
├── ModelStore.js, Physics.js, Palette.js, VisualCanvas.qml
├── SettingsDocument.qml, SettingsQueue.js, EngineFeed.qml
├── assets/omaviz.desktop  (app-launcher entry)
├── bin/omaviz-engine   (COMMITTED engine binary)
├── tests/*.test.cjs     (node: config, physics, protocol, palette, queue, engine)
├── engine/              (Rust omaviz-engine source)
├── build.sh             (cargo build → bin/)
├── install.sh           (copy plugin files + omarchy plugin enable)
├── uninstall.sh         (remove plugin)
├── preview.png          (marketplace preview)
└── docs/screenshots/    (README tour captures)
```

---

## 10. Feature roadmap

| # | Feature | Status | Progress |
|---|---------|--------|---------:|
| 1 | Single-package plugin (QML + bundled native engine) | Shipped | 100% |
| 2 | Zero-build drop-in install | Shipped | 100% |
| 3 | PipeWire audio capture → 32-band spectrum | Shipped | 100% |
| 4 | Mini bar visualizer (Canvas-2D) | Shipped | 100% |
| 5 | Settings panel (peaks toggle, peak fall speed) | Shipped | 100% |
| 6 | Read-only audio source indicator | Shipped | 100% |
| 7 | Desktop detach window (Canvas-2D) | Shipped | 100% |
| 8 | Detach/Attach toggle with mini pause | Shipped | 100% |
| 9 | Peak-hold markers with configurable falloff | Shipped | 100% |
| 10 | Theme-dominant gradient colors | Shipped | 100% |
| 11 | TDD: engine (Rust) + plugin (node) suites green | Shipped | 100% |
| 12 | GPU exploration | Canvas unchanged; backend diagnostics and parity harness | docs/GPU_EXPLORATION.md |
| 13 | Additional backends (PulseAudio/JACK/ALSA) | Planned | 0% |

### Runtime ownership (8.5)

SettingsDocument owns config reads and serialized writes via SettingsQueue.
EngineFeed owns engine start/stop/retry and protocol validation for both surfaces.
ModelStore contains pure functions; there is no parallel mutable JS store.
Native component tests use an isolated config and software/offscreen rendering.

Settings control pairs use a shared row height, and the bottom-right footer reads
the installed version from `manifest.json`. Releases provide an exact-commit
marketplace verification link; automatic submission is optional and credential-gated
(see README).
