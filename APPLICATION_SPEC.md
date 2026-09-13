# omaviz — Application Specification (v7.12.0)

> **Plugin id:** `org.omaviz.visualizer`
> **Version:** 7.10.0 (spec + manifest, git tag)
> **Status:** Single-package Omarchy QML plugin. Audio analysis is bundled as
> one native binary (`plugin/bin/omaviz-engine`) shipped **inside** the plugin
> directory. No systemd service, no Unix socket, no `~/.local/bin` binaries.

This document is the **source of truth** for what ships and how it is verified.

---

## 1. Goals & Non-Goals

**Goals**
- React to system playback audio (not microphone) via the default audio sink.
- Ship as a **single plugin directory** — every dependency (QML, JS, native
  engine binary) lives under `~/.config/omarchy/plugins/org.omaviz.visualizer/`.
- **Zero-build install (Architecture A):** the engine binary is **committed**
  at `plugin/bin/omaviz-engine`. Installing the plugin is just copying the
  directory + `omarchy plugin enable` — no Rust toolchain required.
- Canvas-2D based rendering (no GL shader dependency for default path).
- Winamp-style spectrum analyzer with peak-hold markers.

**Non-Goals (v7.6.1)**
- No microphone monitoring.
- No backend switching UI (source is auto + displayed, not chosen).
- No GPU/ShaderEffect (removed in favor of Canvas-2D).

---

## 2. Architecture (v7 — single package)

```
plugin/  (deployed to ~/.config/omarchy/plugins/org.omaviz.visualizer/)
├── manifest.json
├── BarWidget.qml   (spawns bin/omaviz-engine, parses its stdout)
├── Panel.qml       (settings: Peaks toggle, Peak fall speed)
├── Desktop.qml     (detached window)
├── Model.js        (.pragma library: config IO, spectrum parse)
├── VisualCanvas.qml  (Canvas-2D renderer — DEFAULT)
├── shaders/visual.frag
├── visuals/*.toml  (equalizer / wave / fire)
├── bin/
│   └── omaviz-engine   (Rust: capture → FFT/DSP → JSON lines on stdout;
│                         COMMITTED artifact — see Architecture A, §2)
└── tests/{model,glspectrum}.test.cjs
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
   │  SplitParser → Model.parseSpectrumLine
   ▼
Model.spectrumData { bands, energy, beat, silent, source }
   ▼
VisualCanvas (Canvas-2D) — used by mini, preview, AND desktop
```

---

## 3. Files

| File | Purpose |
|------|---------|
| `BarWidget.qml` | Waybar mini widget. Spawns engine, renders spectrum, handles detach/attach. |
| `Panel.qml` | Settings panel. Shows PREVIEW, Peaks toggle, Peak fall speed (Slow/Med/Fast), SOURCE readout. |
| `Desktop.qml` | Detached visualization window. Same VisualCanvas renderer, larger. |
| `VisualCanvas.qml` | **DEFAULT** Canvas-2D renderer. Used by mini, preview, and desktop. |
| `VisualCanvasGL.qml` | Legacy GPU/ShaderEffect renderer. Not used by default. |
| `Model.js` | Config I/O, spectrum parsing, default config with peaks/peakFalloff. |

---

## 4. Rendering — `VisualCanvas.qml` (Canvas-2D, default)

The same renderer is used for **all three contexts** (mini, preview, desktop).
Only the container size and position change.

### Rendering parameters (set by parent)

| Property | Default | Description |
|----------|---------|-------------|
| `gapPx` | config `gap` | Space between bars in pixels (0 in spikes) |
| `minBarHeight` | `0` | Minimum bar height (0 = allow flat) |
| `peaks` | `true` | Show peak-hold markers (2px white; 1px hot in spikes) |
| `peakFalloff` | `0.5` | Peak falloff speed (0=holds, 1=falls fast) |
| `spikes` | `false` | Dense thin gapless flame spikes (~2px, width-derived count) |
| `spikeBars` | `0` | Spike count cap (0=auto; mini passes 32) |
| `fire` | `false` | Vertical red→orange→white-hot flame gradient (container-shared) |
| `splits` | `false` | Winamp segments: 3px blocks + 1px gaps (preview/desktop) |
| `sensitivity` | `1.0` | Input gain multiplier |
| `themeBottom`/`themeTop` | amber | Theme-anchored colors; live shell accent when `colorSync` |

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

## 5. Settings Panel (v7.8.0)

**PREVIEW**: Live visualization (same renderer, larger) + helper text below
(left-aligned, muted): double-click opens the desktop window.

**OPTIONS** (live-wired via `writeVizOption(s)` — disk + instant local update):
- **Peaks**: Toggle — peak-hold markers on all surfaces (default on)
- **Peak fall speed**: Slider 0..1, shown only when Peaks on (0=holds, 1=fast)
- **Spikes**: Toggle — dense gapless flame spikes; auto-enables Fire on
  select, auto-disables on deselect (single multi-key write)
- **Fire**: Toggle — vertical flame gradient, all surfaces
- **Stacks**: Toggle — segmented bars (preview/desktop only)

**SOURCE**: Read-only audio source indicator (e.g., "PipeWire · default sink")

---

## 6. Config properties (`~/.config/omaviz/config.toml`)

```toml
[audio]
sensitivity = 1.0
smoothing = 0.5
bands = 32

[mini]
gap = "1"
width_scale = "1.5"
visual = "equalizer"
style = "classic"
color_sync = false

[desktop]
active = "false"
heartbeat = "0"
gpu = "true"
color_source = "theme"
density = 128
custom_color = "#5ec8ff"
theme_bottom = "#e68e0d"
theme_top = "#f59e0b"
fire = "false"
peaks = true
peak_falloff = 0.5
spikes = "false"
splits = "false"
```

---

## 7. Detach / desktop window lifecycle

- **Double-click** mini or preview → opens detached desktop window
  (right-click removed); **single-click** mini → settings panel
- Mini visibility follows shared `desktop.active` + 2s heartbeat lease —
  any launch path (bar, app launcher, `SUPER+V`) converges; close from any
  path brings the mini back
- Desktop self-claims the flag on open; `onClosing` clears it with a flush
  delay then `Qt.quit()` (no zombie windowless processes)
- Desktop height capped at 300px, bottom-anchored

---

## 8. Operational notes

- Install: `./install.sh` (zero-build by default, uses committed binary)
- Rebuild engine: `./install.sh --build`
- Uninstall: `./uninstall.sh`
- No systemd, no socket, no `~/.local/bin`

---

## 9. Repository structure

```
omaviz/
├── APPLICATION_SPEC.md  (this file)
├── engine/              (Rust omaviz-engine source)
├── plugin/              (QML/JS — copied verbatim to live dir)
│   ├── manifest.json, BarWidget.qml, Panel.qml, Desktop.qml
│   ├── Model.js, VisualCanvas.qml, VisualCanvasGL.qml
│   ├── bin/omaviz-engine   (COMMITTED engine binary)
│   └── tests/{model,glspectrum}.test.cjs
├── build.sh             (cargo build → plugin/bin/)
├── install.sh           (copy plugin dir + omarchy plugin enable)
├── uninstall.sh         (remove plugin)
├── ADR/                 (Architecture Decision Records)
└── archive-v6/          (ARCHIVE: prior daemon design)
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
| 12 | GPU/ShaderEffect visuals (legacy fallback) | Shipped | 100% |
| 13 | Additional backends (PulseAudio/JACK/ALSA) | Planned | 0% |
