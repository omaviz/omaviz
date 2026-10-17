# omaviz — Application Specification (v8.10.1)

> **Plugin id:** `org.omaviz.visualizer`
> **Version:** 8.10.1 (spec + manifest; release tag follows merge)
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
| `stacks` | `false` | Winamp-style stack rows, touching vertically with no dark seams (desktop rows scale via stackScale) |
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

The panel uses an opaque theme background and Spectrum / Waveforms / Particles / Radial category choices. Waveforms contains Waves, Strings, and Siri; Particles contains Bokeh, Pixel Wave, and Cosmos; Radial contains Orbit, Spiral, and Tunnel. Groups with fewer than five choices use direct buttons. Only relevant controls are shown.

- **LOOK** appears for Spectrum: geometry, peaks, and reflection.
- **COLOR** offers Theme / Custom / Artwork / Flame for Spectrum and
  Theme / Custom / Flame for Waves,
  Prism / Custom for Siri, Original / Custom for Strings, and Theme / Custom / Artwork
  for Bokeh, Pixel Wave, and Orbit, which also offer Original reference colors. Color editors
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
**Disable plugin** stops capture, releases the desktop lease to close its process, then
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
- Mini and desktop animate simultaneously. Shared `desktop.active` + a 2s
  heartbeat lease in `desktop-state.toml` (6s expiry) tracks popout liveness.
  The app launcher saves `enabled=true`, enables the plugin, and opens one
  desktop instance; launching after Disable restores both surfaces.
- Settings writes are serialized and remain optimistic until acknowledged.
  Explicit `stacks`/`artwork` settings override legacy aliases.
- Desktop self-claims the flag on open; `onClosing` clears it with a flush
  delay then `Qt.quit()` (no zombie windowless processes)
- Desktop window is 600×200; the visualization container is bottom-anchored
  and fills `max(100px, 95% of window height)`
- No title bar: a compact now-playing card, at most 480px wide, fades in on pointer movement
  at the bottom center. Track, artist, and album details sit beside the poster; square actions occupy the top-right corner. Narrow windows move the artwork/details row below the actions.
  Track titles wrap to two lines on wide cards and elide on narrow cards; albums have their own line, and hovering over
  the details exposes full metadata in a tooltip.
  Cosmos image credits appear below the action buttons, inside the same panel.
  Play/pause appears only when the selected MPRIS player supports the current
  action. Actions have keyboard and accessibility support; the card fades
  after 30 seconds without pointer activity, even while hovered. Moving again or pressing Tab reveals it; media actions restart the deadline.


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

`[desktop] visual = "Bars" | "Waves" | "Strings" | "Siri" | "Orbit" | "PixelWave" | "Bokeh" | "Tunnel" | "SolidTunnel" | "Cosmos"` selects the mode.
When absent or invalid, legacy `scope = true` selects Waves, otherwise
Bars. Explicit visual takes precedence. UI selection writes visual and the
legacy scope flag atomically. All three waveform modes request the engine wave
feed. Strings leaves the background transparent. Independent strands rotate
around a uniform virtual pipe at different pitches. Waveform energy expands
the pipe height, spectral bands pulse individual strand radii, and waveform
samples add local vibration. Selective strand defocus and broad soft foreground
strands provide depth.
The common waveform thickness control affects Waves and Strings. Legacy
`Oscilloscope` values migrate to Waves; the former layered Waves renderer is retired.
Siri keeps the existing cyan/blue/violet ribbon renderer as its default.
The **Classic Siri** style selector persists `desktop.siri_classic`
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

Desktop Waves and Siri retain a centered 3:1 drawing area. Strings fills the
desktop area to increase its motion and depth in taller/wider windows; its
carrier frequency and waveform coupling yield broader, audio-responsive curves.
Spectrum fills the available window and grows bar width from roughly 10 to 18px
between 600 and 1200px. Stack tiles leave one physical pixel of separation.
The artwork blur is unloaded whenever leaving Bars, avoiding stale cached art.


### Historical review corrections

- Ingest each queued PCM chunk before rate-limited FFT analysis; do not reinsert
  old samples on heartbeat frames. Honor SPA valid-data offsets and stride.
- Capture disconnects clear the active frame layout and exit for EngineFeed retry.
- `{wave:[...]}` now carries a peak-preserving 128-point envelope and optional
  `wave_rms` (finite 0–1 full-window RMS). Native submit accepts an optional RMS
  argument; missing metadata retains legacy waveform-derived loudness.
- Settings preview precedes tuning; numeric controls are unboxed, show values,
  and Response exposes the persisted 0.1–4 range. Siri style is a selector.
  Save errors and invalid hex input are visible. Exit is labeled Disable plugin.
- Remote MPRIS artwork is intentionally fetched; audio is never uploaded.
- Native offscreen verification requests OpenGL 3.3 and fails shader errors.


## Review follow-up: density, recovery, controls, and looks

- Preserve mini (128 analysis bands, normally 32 displayed) and desktop (256 analysis bands, size-adaptive display) resource/density differences. Retain the original FFT band mapping.
- Capture retains interleaved channels. Spectrum and RMS average channel power; the audio trace uses the strongest channel window. PCM is sanitized before processing. PipeWire processing is outside the RT callback thread; a four-chunk mailbox evicts oldest audio and removes the forwarding thread. Synthetic sources use a bounded channel.
- EngineFeed accepts quiet heartbeats as healthy. Missing valid spectrum for four seconds clears stale bands/waveforms, terminates the process (SIGKILL after 500 ms if necessary), and uses the existing retry backoff. UI exposes Connecting, Listening, Listening · quiet, Recovering and Stopped.
- Categories and sub-options use buttons for fewer than five choices and dropdowns otherwise, with no search. Category selection restores its previous visualization. Appearance/motion are remembered per visualization in `looks.<mode>`. Color mode and geometry are exclusive enum choices with legacy flag migration. Active values remain in the existing desktop/audio sections for compatibility. Once explicit `color_mode`/`geometry` keys exist, edit these keys rather than legacy boolean flags.
- Every appearance/motion edit automatically updates its per-visualization profile in one queued write. No Save / Restore / Reset or starting-look presets. Selection buttons have square corners. Global enable, mini sizing, and theme snapshots are not overwritten by look changes.
- Desktop transport is a translucent bottom panel with poster, track text, capability-aware Previous / Play-Pause / Next, and Close at the right. A shared MediaSession owns selection and transport; palette extraction consumes that selected player. At narrow sizes track text gives way to the poster/actions.
- F11 toggles fullscreen; Escape returns to windowed mode before closing; Ctrl+Left/Right switches visuals through the bar's IPC writer. Windowed size is persisted in desktop-window.ini, separate from config.toml and the runtime lease.
- The settings panel uses bounded height and scrolling, without polling-based size locking.
- Native tests exercise transport, selection thresholds, keyboard/mouse actions and full panel scrolling; real QML I/O tests exercise stalls, invalid frames, forced termination and recovery. Source-string layout/performance tests were removed. Benchmark results require an actual hardware-capable API and at least 120 rendered frames.
- Native binaries embed a source/shader input fingerprint; CI checks it before rebuilding to catch stale bundles. This is not a reproducibility or security attestation.

### Clipboard boundary

Hex colors use bounded key-only entry, not Qt TextInput/TextEdit. Hidden or visible controls never read the system clipboard; paste and IME commit payloads are ignored. Type six hex digits, Enter to apply, Escape to cancel. MPRIS text remains PlainText.


## 8.9.0 — Particle and radial catalog additions

The category selector includes Spectrum, Waveforms, Particles, and Radial.
Particles offers Bokeh, Pixel Wave (`PixelWave`), and Cosmos; Radial offers Orbit, Spiral (saved ID `Tunnel`), and Tunnel (saved ID `SolidTunnel`). Saved IDs and per-mode looks remain stable through the display-name changes.
Each uses the existing category memory, per-visual look persistence, automatic saving,
and Response control. Their color choices are Original, Theme, Custom, and Artwork; the mini
also supports monochrome. Spectrum-only geometry, peak, flame, and dot-grid controls
are hidden. Waveform thickness remains exclusive to Waves and Strings.

All three draw through VisualCanvas and the shared native geometry backend, using
the existing full spectrum protocol without new capture modes. Orbit draws independent
rounded concentric arcs whose lengths and brightness follow smoothed frequency ranges.
Pixel Wave draws a perspective field of squares with eight delayed spectral rows (four
in the mini). Bokeh draws drifting discs with changing focus, audio-driven brightness,
and energy-driven cloud spread. Desktop modes use the full available drawing area;
Orbit and Bokeh keep their circular proportions centered within it. Below 48px height,
element counts decrease. Audio releases fade and the animation clock settles after
1.6 seconds of silence; hidden surfaces retain the existing sleep behavior.


Verification: `tests/catalog-visual.py` captures production VisualCanvas instances
for motion, generated audio, mini size, artwork colors, monochrome, resize, and
silence with final sleep/empty-image assertions. `tests/catalog-feed.cjs` checks
real EngineFeed transitions from Siri through Orbit, Strings, Pixel Wave, and
Bokeh, including settling after capture stops. Native controls verify the new
palette choices and viewport bounds across normal, wide, tall, and minimum sizes.


## 8.9.1 — Retained particle/radial shaders and reference refinement

Orbit, Pixel Wave, and Bokeh use one shared retained Ambient scene-graph node,
a vertex shader for position/shape and a fragment shader for anti-aliased arcs,
squares, and lens-like soft discs. Geometry rebuilds only when mode, dimensions,
or pixel scale change. Frame updates upload a bounded uniform buffer containing
24 smoothed frequency envelopes, time, palette, and a 20-column / 8-row history;
the CPU performs audio smoothing/history, not per-frame geometry construction.
The previous CPU mesh implementations of these modes are removed.

Original is a separately persisted palette choice, alongside Theme, Custom, and
Artwork. Fresh particle/radial looks default to Original with the existing cached
artwork backdrop enabled; saved explicit looks remain intact. Original uses
neutral silver for Pixel Wave, white/cool lens discs for Bokeh, and silver arcs
with a warm inner accent for Orbit. Optional artwork backdrops reuse the existing
cached blur Loader and unload completely when disabled or unsupported. Selecting
a palette other than Artwork also clears the backdrop in the same settings write;
the backdrop toggle can still be enabled independently afterward.

Orbit sways its outer arc group while inner arcs articulate independently,
with frequency-driven lengths and angular offsets. Bokeh distributes 64 discs
through a drifting volume; PCM loudness expands the cloud, moves its focus plane,
and changes highlights. Neither uses the old shared loudness-speed clock.
Pixel Wave transports delayed square rows upward from a bright leading edge,
shrinking and fading into depth. Spectral and waveform history advances every
105ms with interpolation between updates. The contour is derived only from the
recorded waveform and spectral shape; no clock-driven sine wave moves it sideways.
This recreates the reference video's forward travel instead of in-place flutter.
Mini geometry uses 4 arcs, 16 discs, or 12 columns / 4 rows.

Full-window PCM RMS drives Bokeh, Orbit, both tunnels, and Cosmos when supplied,
with a spectral fallback for older frames. Pixel Wave retains its spectral response.

`ambientresponse-test` covers PCM dynamic range, frame batching, history clearing,
nonfinite inputs, and settling. `tests/ambient-benchmark.py` compares matched
inputs against a saved runtime in alternating trials and asserts one retained
mesh build during steady animation. Its CPU/frame results are measurements for
the tested backend and workload; visual refinement is not an image-parity claim.


Local profiling (AMD Radeon Pro 580X / OpenGL, 960×540, two alternating trials
per version, identical synthesized full-spectrum inputs) reduced average CPU
submission from 0.1651→0.0209 ms for Orbit, 0.0602→0.0228 ms for Pixel Wave, and
0.5715→0.0218 ms for Bokeh. Each new steady-state run built its mesh once.
Average GPU p95 was 0.1522→0.1434 ms, 0.1959→0.2135 ms, and 0.2006→0.2169 ms,
respectively. Pixel Wave and Bokeh spend slightly more GPU time on the refined effects;
these measurements do not promise identical gains on other hardware or inputs.

### Review hardening

Installer updates preflight incoming runtime names before deleting managed
files. An unowned file or directory collision fails without modifying the
installation; `--force` backs up the existing tree before replacement.

### Tunnel

Radial → Spiral (saved ID `Tunnel`) uses the shared retained Ambient GPU renderer on mini, preview, and desktop surfaces. Perspective rings extend logarithmically into the distance around a drifting vanishing point; pearls float inside the pipe with no background stars or space layer. Integrated music energy controls travel speed, low bands gently breathe the walls, and high bands brighten the pearls. Original colors blend cyan, violet, and gold; Theme, Custom, Artwork, and monochrome use the existing color controls. Geometry is clipped to the viewport. Compact surfaces retain at most 12 rings and 4 pearls; larger surfaces retain at most 22 rings and 8 pearls. A smoothly gated ring population increases with PCM loudness, leaving roughly one third visible during quiet passages. Audio fades out and animation sleeps after silence, using the existing ambient envelope.

### Renderer audio response

Bokeh and Orbit loudness use a gentle power curve so quiet PCM remains visible
while retaining contrast between passages; sensitivity still applies once.
Pixel Wave retains its spectral envelope. Both tunnels and Cosmos use PCM RMS with a spectral fallback. The Rust DSP,
file replay implementation, and engine binary remain the original v8.9.1 release.

### Tunnel and app resume

Radial → Tunnel (`SolidTunnel`) is separate from Spiral (`Tunnel`).
A full-viewport opaque shader traces the inside of a curved cylindrical passage.
A curved camera path, steady viewpoint, forward travel, diffuse lighting,
staggered precast concrete segments, recessed joints, bolt pockets, and restrained
depth haze create an immersive passage. Original uses concrete with warm/cool
illumination; the other palettes tint the lining.
Music intensity controls broad left/right turns through an 850ms smoothing envelope. Camera orbit and continuous roll are removed, and wall breathing is restrained. The passage has no fixed
black end cap, and opaque shading prevents artwork from showing outside it.
Music modulates travel and wall lighting. Bokeh adds modest per-band size and
brightness response plus onset accents without changing its drift/focus design.
The app entry point is Launch.qml; settings save before plugin enable, and
Desktop opens with duplicate-instance protection. Mini capture stays active
while Desktop is open. The Rust engine source and binary are unchanged.

### Music-shaped wave and tunnel depth checks

`tests/pixel-music.cjs` renders held uniform input to reject autonomous wave
carriers, then compares equal-energy bass and treble spectra to verify the
contour follows the input. The cached emitted shapes still recede and fade.
The spiral uses logarithmic ring depth to approach a distant endpoint without
the former large central gap. It has no background starfield.
The segmented tunnel uses bounded interior tracing and filtered distant joints
to keep its curved throat smooth. Both remain silent-settling and support
existing palettes and monochrome. These changes do not alter Rust DSP or the
original v8.9.1 engine artifact.

### Cosmos and segmented tunnels

Particles → Cosmos is an opaque, full-viewport flight through projected stars
at multiple depths. The Milky Way backdrop uses the unmodified 4000×2000 ESO
all-sky photograph (eso0932a, credit ESO/S. Brunier, CC BY 4.0), embedded in the
native resource bundle and sampled with linear/mipmap filtering. A slow oblique
projection preserves the real central bulge and dust lanes. Theme, Custom, and
Artwork tint the central glow through the existing palette; Original retains
natural color. There is no perimeter vignette or edge darkening. Foreground
stars use circular halos that reach zero alpha before the quad boundary,
leaving no rectangular background when stars approach. Three small spiral
galaxies approach with parallax along the outer field, outside the
central flight corridor. There is no black hole or lens.

The retained star mesh has 320 stars in the mini and 3840 on larger surfaces.
Population and luminosity do not respond to loudness or onsets. Music controls
the integrated travel clock only; both star layers advance through depth,
with the distant population travelling more slowly than nearby stars. All
stars grow and brighten smoothly as they approach, with depth fades at recycling
boundaries. Star sizes scale with
desktop dimensions. The mode fades/settles during silence and supports existing
palettes and monochrome. Stars keep their natural temperatures regardless of Theme, Custom, or Artwork
palette changes; only explicit monochrome overrides star colors. Palette tinting
is restricted to the diffuse core, retaining resolved photographic star highlights.
The shared visualization has no text overlay. The photograph credit is linked
below the desktop hover panel actions; the mini tooltip carries the same credit. Full asset
provenance and runtime modifications are in renderer/textures/ATTRIBUTION.md.
The native source stamp covers the photograph and its attribution as inputs.

Tunnel uses eight staggered concrete segments per lining ring, antialiased
recessed joints, bevel shading, bolt pockets, and diffuse illumination.
Spiral has no stars and uses fewer luminous rings; its density, radius,
width, light, and axis shift respond to music. Both tunnels and Cosmos use
PCM RMS when supplied, with a spectral fallback. An integrated travel clock
follows loudness without jumping when volume changes. Other modes and the
Rust engine are unchanged. Display names are resolved through visualLabel,
including desktop titles and the mini tooltip; saved IDs remain compatible.

The rendering approach follows NVIDIA GPU Gems chapter 39's compositing model
and Unreal Engine's distinction between scattering, extinction and emission:
https://developer.nvidia.com/gpugems/gpugems/part-vi-beyond-triangles/chapter-39-volume-rendering-techniques
https://dev.epicgames.com/documentation/en-us/unreal-engine/volumetric-fog-in-unreal-engine
The segmented lining is inspired by precast tunnel liners:
https://www.boringcompany.com/prufrock
Motion reference supplied by the user: https://www.youtube.com/watch?v=UNOmaFs6KaY

### Track-change shuffle and flame spectrum

Shuffle is an accessible compact toggle at the right of the preview header, opposite the Preview label, without helper text. The bar owns
MPRIS track-change detection and settings writes. A 500ms debounce coalesces
track metadata; activation, player replacement, pause, and same-track metadata
updates do not pick another look. A different mode is selected on each change.
Mode-specific options vary Spectrum geometry/palettes and Siri style/travel,
with Original/Theme/Custom palettes for ambient modes. No audio parameters change.
The transient JSON look lives in `[shuffle].look`; `[desktop].shuffle` enables
it. The saved mode, look profiles, and category selections remain underneath.
Disabling Shuffle restores them, including after restart; manual mode selection
also disables it. Mini, preview, and desktop use a shared transition controller:
500ms fade-out, swap at zero opacity, 700ms fade-in. New settings arriving during
a fade are coalesced, with a subsequent transition if needed.

Spectrum Spikes now uses one transparent shader field fed by smoothly interpolated
frequency energy, rather than bar triangles. Upward-advected multi-scale noise
warps the flame tongues, opens rolling gaps, and shapes temperature-like cores.
The selected palette and explicit monochrome remain supported, as does a subdued
reflection. Silence extinguishes the field; flame geometry has no rigid peak caps.
CPU bar/peak physics, other Spectrum geometries, and the v8.9.1 engine are unchanged.
Research: NVIDIA GPU Gems, Chapter 6, Fire in the Vulcan Demo, section 6.1
(https://developer.nvidia.com/gpugems/gpugems/part-i-natural-effects/chapter-6-fire-vulcan-demo).

### v8.10.1 — Marketplace artwork bounds and live preview evidence

ArtworkPalette accepts bounded PNG/JPEG/WebP input: at most 12 MiB, 4,194,304
source pixels, and 8,192 pixels in either dimension. PNG framing is validated
before Qt: only IHDR, PLTE, IDAT, IEND, and bounded tRNS chunks reach the decoder.
Text, compressed ICC profiles, and all other ancillary chunks are discarded
without decompression, including after IDAT. Unknown critical chunks, truncated
frames, invalid dimensions, and excessive chunk counts are rejected. Format
autodetection and unrelated image plugins are disabled. No global Qt image
allocation setting is changed. Fetches have both transfer and absolute ten-second
deadlines and a bounded reply buffer.

The decoded raster is reduced to at most 192×192 and copied into a fresh image
containing pixels only. This image supplies the palette and a generated PNG data
URL for both the poster and cached backdrop. QML never decodes an original MPRIS
artwork URL. Clearing/changing artwork cancels the request and clears both outputs.
A standalone Text content item forces metadata tooltips to PlainText; static
credits remain the only styled markup in the transport card.

The artwork CTest exercises repeated compressed PNG chunks before and after IDAT
whose total expansion exceeds 1 GiB, in a subprocess with a 256 MiB address-space
limit and a five-second deadline. It also verifies ordinary PNG/JPEG decoding,
metadata-free thumbnails, oversized/malformed/unsupported input, cancellation,
and unchanged host allocation limits. The GPU backdrop regression uses the real
sanitized-thumbnail path and verifies complete pixel removal on deselection.

The refreshed marketplace preview contains all ten visualizations plus Bars,
Stacks, and Classic Siri styles, using live PipeWire audio. Mini and Settings
are actual installed screenshots. tools/capture-preview.py creates bounded native
source captures, records audible frames/source and renderer digest, and leaves
user settings untouched. tools/render-preview.py composes the 2400×1800 image
without stretching or repainting screenshots. Provenance and layout references
are in docs/screenshots/marketing/captures.json.
