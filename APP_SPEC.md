# omaviz — Application Specification (v8.7.0)

> **Plugin id:** `org.omaviz.visualizer`
> **Version:** 8.7.0 (spec + manifest, git tag)
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
- GPU scene-graph rendering through one bundled Qt Quick geometry module.
- Winamp-style spectrum analyzer with peak-hold markers.

**Non-Goals (v7.6.1)**
- No microphone monitoring.
- No backend switching UI (source is auto + displayed, not chosen).
- No MilkDrop preset engine in this release (projectM remains a future extension).

---

## 2. Architecture (v7 — single package)

```
repo root = the plugin (deployed to ~/.config/omarchy/plugins/org.omaviz.visualizer/)
├── manifest.json
├── BarWidget.qml   (spawns bin/omaviz-engine, parses its stdout)
├── Panel.qml       (settings: Peaks toggle, Peak fall speed)
├── Desktop.qml     (detached window)
├── ModelStore.js   (.pragma library: config store — IO, defaults, get/set)
├── Physics.js      (.pragma library: shared bar/peak motion model)
├── VisualCanvas.qml  (shared GPU renderer)
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
EngineFeed (one Process per active surface)
   │  SplitParser → Store.decodeFrame
   ▼
Observable QML bands, wave, silent, source
   ▼
VisualCanvas (native GPU geometry) — used by mini, preview, AND desktop
```

---

## 3. Files

| File | Purpose |
|------|---------|
| `BarWidget.qml` | Waybar mini widget. Spawns engine, renders spectrum, handles detach/attach. |
| `Panel.qml` | Settings panel. VISUALIZATIONS cards, live PREVIEW, LOOK / COLOR / MOTION groups, collapsed ADVANCED, SOURCE readout. |
| `Desktop.qml` | Detached visualization window. Same VisualCanvas renderer, larger. |
| `VisualCanvas.qml` | shared GPU renderer. Used by mini, preview, and desktop. |
| `ModelStore.js` | Config store: TOML I/O, defaults/validation, reactive get/set, spectrum parsing. |
| `Physics.js` | Bar/peak motion model (instant attack, rate-limited release, peak sustain). Unit-tested. |

---

## 4. Rendering — `VisualCanvas.qml` (shared GPU geometry)

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
All modes use the same native scene-graph geometry backend. FrameAnimation
drives fixed 60 Hz physics steps with bounded catch-up, independently of audio
arrivals. Vertex colors provide theme/custom/flame gradients; layered antialiased
ribbons provide scope and Waves. Settled silent and hidden instances stop their
frame clock. CPU/GPU acceptance budgets and measurement requirements live in
GPU_PLAN.md; runtime measurements are required before claiming compliance.
While the detached desktop is active, the bar suspends its duplicate capture
engine when the settings preview is closed; opening the preview or closing the
desktop resumes that feed.

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

The panel uses an opaque theme background and a top-level Spectrum / Waveforms dropdown. Waveforms has a second dropdown
for Waves (the oscilloscope/audio trace), Strings, and Siri (luminous waves). Only relevant controls are shown.

- **LOOK** appears for Spectrum: geometry, peaks, and reflection.
- **COLOR** offers Theme / Custom / Artwork / Flame for Spectrum and
  Theme / Custom / Flame for Waves,
  Prism / Custom for Siri, and Original / Custom for Strings. Color editors
  and presets appear only for Custom or Flame. Custom gradients accept any
  start/end hex colors and an optional removable middle color. Two-color presets reset to two stops; Peacock supplies editable
  teal, violet, and gold stops, including for Strings. Flame retains its independent pair. Gradient direction is
  available for custom Spectrum colors.
- **MOTION** exposes Response. **FINE TUNING**, collapsed initially, reveals
  peak fall speed when peaks are enabled, line thickness for Waves and Strings,
  mini mono, Spectrum linear fall, non-decorative dot grids, and backdrop.
- **PREVIEW** is last: a 132px live visualization on a pure black canvas,
  without the atmospheric wash. Clicking it opens the desktop visualizer.

Custom middle stops persist as `bar_color_middle_enabled` and
`bar_color_middle` under `[desktop]`, with backward-compatible defaults.
All surfaces share these settings and the native renderer.

Spectrum Artwork mode (`artwork_colors = true`) extracts three dominant hue
families from the selected MPRIS cover, sampled once at 48×48 per artwork change.
It colors bars on all surfaces and adds a cover-derived gradient over the blurred
desktop backdrop. The backdrop can be disabled independently. Missing, failed,
or unsupported artwork falls back to the theme; stale replies are discarded.
The extractor accepts local files and HTTP(S), with a 10-second timeout and
12 MiB download limit. The settings preview always remains black.

All controls are live-wired via `writeVizOption` / `writeVizOptions`
(atomic multi-key) / `writeAudioOption` — disk write + instant local update.

**Retired from UI, still honored in code**: `artwork_mode`/`immersive`
migrate to spectrum + backdrop on; `min_bar_height`/`splits` are gone (bar
floor is unconditional; Stacks is the canonical key).

**SOURCE**: Read-only audio source indicator (e.g., "PipeWire · default sink")
in the persistent footer. The header shows Omaviz and its installed manifest
version beside the On/Off switch. When Off, content unloads and the panel
shrinks to the header, helper, and footer. Capture pauses; an open desktop stays
open with a paused label and media controls. On resumes visualization in place.
**Exit** stops capture, releases the desktop lease to close its process, then
unloads the plugin via `omarchy plugin disable`. It does not depend on a settings
save completing and never quits the shared Omarchy shell.

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
gpu = true
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
- No title bar: an inset 88px now-playing card fades in on hover, with 64px
  artwork (independent of backdrop), source, title, artist, and close action.
  Play/pause appears only when the selected MPRIS player supports the current
  action. Actions have keyboard and accessibility support; the card fades
  after leaving the window.


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
├── ModelStore.js, Physics.js, VisualCanvas.qml
├── assets/omaviz.desktop  (app-launcher entry)
├── bin/omaviz-engine   (COMMITTED engine binary)
├── tests/*.test.cjs     (node: modelstore, physics, qml, engine, perf, panel)
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
| 4 | Mini bar visualizer (GPU geometry) | Shipped | 100% |
| 5 | Settings panel (peaks toggle, peak fall speed) | Shipped | 100% |
| 6 | Read-only audio source indicator | Shipped | 100% |
| 7 | Desktop detach window (GPU geometry) | Shipped | 100% |
| 8 | Detach/Attach toggle with mini pause | Shipped | 100% |
| 9 | Peak-hold markers with configurable falloff | Shipped | 100% |
| 10 | Theme-dominant gradient colors | Shipped | 100% |
| 11 | TDD: engine (Rust) + plugin (node) suites green | Shipped | 100% |
| 12 | Shared GPU geometry + Waves | Implementation; acceptance tracked in GPU_PLAN.md | Pending verification |
| 13 | Additional backends (PulseAudio/JACK/ALSA) | Planned | 0% |

### Native renderer packaging (8.5)

`native/libomavizrenderer.so` and `native/qmldir` ship with every install.
Build with `./build.sh` using Qt 6.11+ development files and CMake. The shipped
binary targets Linux x86_64 and Qt 6.11+ public APIs. VisualCanvas.qml remains
the only surface-facing rendering API; renderer/geometry.cpp implements its
shared GPU drawing. The legacy `gpu` key does not switch rendering paths.

`[desktop] visual = "Bars" | "Waves" | "Strings" | "Siri"` selects the mode.
When absent or invalid, legacy `scope = true` selects Waves, otherwise
Bars. Explicit visual takes precedence. UI selection writes visual and the
legacy scope flag atomically. All three waveform modes request the engine wave
feed. Strings leaves the background transparent and drives individual strand
amplitude from spectral bands. Each strand's carrier remains fixed in x;
audio excites standing vibration and adds small local
motion from waveform samples, without horizontal phase travel.
The common waveform thickness control affects Waves and Strings. Legacy
`Oscilloscope` values migrate to Waves; the former layered Waves renderer is retired.
Siri keeps the existing cyan/blue/violet ribbon renderer as its default.
**Classic Siri style**, beside **Left to right motion**, persists `desktop.siri_classic`
(default false). Both settings apply independently on mini, preview, and desktop.
`renderer/siriribbonnode.cpp` preserves the existing ribbons, including their shared
15% amplitude floor and original palette/glow. Switching styles replaces the scene
graph node safely without restarting the audio engine. The optional classic style
uses six independently appearing, vertically mirrored lobes on a fine neutral
axis, visually referenced against Craig Dehner's classic Siri animation and iOS 9
device footage. Red, green, blue, and cyan lobes add light toward white where they
overlap. Monochrome uses normal alpha blending so black remains visible on light
backgrounds; custom colors retain their configured alpha.
`SiriResponse` uses a soft-knee loudness mapping, 18–38 ms attack, and 95–135 ms
release. Six independent spectral RMS controls (<180, 180–450, 450–1000,
1000–2500, 2500–6000, >6000 Hz) use the existing FFT with Hann power compensation.
There is no shared amplitude floor. Each lobe has a smooth birth, growth, decay,
and absent interval; deterministic variation changes its width, location, and
prominence between births while keeping every surface consistent. Legacy
unlabeled input falls back to global RMS. These are reference-informed visual
parameters, not a claim about Apple's proprietary audio mapping.
The default centered mode grows and contracts in place. **Left to right motion**
persists `desktop.siri_travel` (default false) and moves lobes rightward during
their lifetime. It applies to mini, preview, and desktop without restarting the
engine. Silence removes all lobes and settles animation; mini amplification
retains quiet detail without animating silence.
`renderer/sirinode.cpp` retains the smooth lobe mesh and antialias fringe until
size, scale, or style changes. Each frame updates only six position/scale/opacity
uniforms. The vertex shader applies simple transforms without per-vertex sine,
exponential, or normal calculations; no texture or blur pass is added.
The engine's `--siri` feed preserves spectrum metadata and silence detection, emits
six spectral RMS `bands` labeled `band_layout:"siri"`, and represents `wave` as one RMS sample calculated from the
full PCM window. It no longer measures the decimated display snippet, which could
miss tones at its sample-stride frequencies. Siri retains the original display-wave
change identity via an optional `wave_serial` counter, so equal-RMS
audio still wakes a settled visualizer. `OMAVIZ_SIRI_LEGACY=1` selects CPU deformation of the same lobe mesh
for comparison; `tests/renderer-compare.py` runs bounded deterministic native checks.
Strings uses eight strands below 48px height and sixteen elsewhere. Waves preserves
the PCM trace with bounded, smoothed display gain for quiet signals. Strings retains
its carrier/mode bases, ribbon vertices, colors, and index topology on the GPU;
its shader deforms the mesh using the original smoothed excitation and filtered
waveform. `--strings` aggregates the same five-band maxima for each of 16 strands
before serialization, labels the frame with `band_layout: "strings"`, and retains
the full 128-sample waveform and original spectrum metadata. Legacy full-band frames
remain supported. `OMAVIZ_STRINGS_LEGACY=1` selects the original geometry path.
The Spectrum experiment (enabled in this build) retains bar, stack,
spike, wash, peak, and reflection geometry until style,
size, scale, or band count changes. Its vertex shader consumes the existing QML
physics heights and peaks; it preserves pixel snapping, palette splits, and QColor
quantization. Stack tiles above the active height collapse without changing their
spacing. Inputs above 1024 bars use the original geometry path to keep uniform
buffers bounded. `OMAVIZ_SPECTRUM_RETAINED=0` restores the original path. Controlled
desktop probes did not establish a 50% improvement, and retained stack tiles increased GPU work.
`OMAVIZ_BARS_LEGACY=1` overrides the experiment for comparison.
`tests/renderer-benchmark.py` and `tests/renderer-compare.py` accept `Siri`, `Strings`,
or `Bars`; Bars benchmarks also accept `stacks`, `spikes`, or `combined`.
Native geometry nodes are created only once drawable data exists and recreated on mode changes
to reset envelopes and triangle/strip topology.

Desktop config and lease paths resolve directly from Quickshell's XDG/HOME
environment on both surfaces. Completed FileView loads apply fresh settings;
250ms polling remains the fallback. Waveform-feed restarts wait for engine exit.
Capture loss clears both waveform and spectrum output and preserves the selected
compact band layout. Invalid PCM is sanitized before FFT and waveform serialization.
A passive parent HoverHandler observes the whole desktop content tree, keeping
controls visible over child buttons. Playback uses explicit pause/play capabilities
and retains the controlled player after pausing.

## Interaction acceptance updates

Settings custom actions support Tab, Space/Enter, and accessibility activation.
Sliders retain the shell pointer behavior and add arrows/Home/End. Focus scrolling
keeps expanded controls reachable. Hex fields recover from incomplete edits and
continue tracking subsequent preset changes. Dropdown surfaces follow the shell
theme instead of assuming a dark background.

Capture restarts wait for process exit, including rapid mode and Off/On changes;
stale waveform samples are cleared when changing capture flags. Desktop Tab
reveals the action tray, keyboard focus prevents auto-hide, and a 320×160 minimum
prevents the artwork/actions from overlapping in small windows.

Desktop waveform resizing preserves a centered 3:1 drawing area for Waves, Strings,
and Siri, fitting within wide or tall windows without stretching the shapes.
Spectrum fills the available window with width-dependent bar density.
