# omaviz — Application Specification (v7.6.0)

> **Plugin id:** `org.omaviz.visualizer`
> **Version:** 7.6.0 (spec) · manifest `2.0.0` · repo tag `v7.6`
> **Status:** Single-package Omarchy QML plugin. Audio analysis is bundled as
> one native binary (`plugin/bin/omaviz-engine`) shipped **inside** the plugin
> directory. No systemd service, no Unix socket, no `~/.local/bin` binaries.

This document is the **source of truth** for what v7 ships and how it is verified.
The prior multi-process design (daemon + socket + bridge) is archived in `v6/`.

---

## 1. Goals & Non-Goals

**Goals**
- React to system playback audio (not microphone) via the default audio sink.
- Ship as a **single plugin directory** — every dependency (QML, JS, native
  engine binary) lives under `~/.config/omarchy/plugins/org.omaviz.visualizer/`.
- **Zero-build install (Architecture A):** the engine binary is **committed**
  at `plugin/bin/omaviz-engine`. Installing the plugin is just copying the
  directory + `omarchy plugin enable` — no Rust toolchain required. This matches
  Omarchy's native plugin model (every other plugin is a drop-in directory).
- Support **multiple audio backends** behind an auto-detected source mapping.
  v7.6.0 ships **PipeWire only** (plus internal verification backends `gen`
  and `gen=<mode>`/ `file=<path>` used only by the test harness — see §10);
  PulseAudio/JACK/ALSA follow later with **no plugin (QML) changes** —
  the plugin never picks a backend. (The `gen`/`file` verification backends are
  already compiled in; see §4.)
- Keep the existing UI: bar mini, desktop detach, settings panel, GPU
  (ShaderEffect) visuals (Bars/Wave/Fire-style) with the Canvas-2D
  `VisualCanvas.qml` retained only as a legacy fallback. The audio plumbing
  changes; the product does not.
- Show the active audio source in the settings panel (read-only).

**Non-Goals (v7.6.0)**
- No microphone monitoring.
- No backend switching UI (source is auto + displayed, not chosen).
- No separate EGL/wgpu context — rendering uses the QML scene-graph
  `ShaderEffect` only; `VisualCanvas.qml` (Canvas-2D) is a legacy fallback, not
  a goal.

---

## 2. Architecture (v7 — single package)

```
plugin/  (deployed to ~/.config/omarchy/plugins/org.omaviz.visualizer/)
├── manifest.json
├── BarWidget.qml   (spawns bin/omaviz-engine, parses its stdout)
├── Panel.qml       (settings: shows Source: <backend> in AUDIO section)
├── Desktop.qml     (detached window)
├── Model.js        (.pragma singleton: config IO, spectrum parse)
├── VisualCanvasGL.qml (GPU/ShaderEffect renderer — default)
├── VisualCanvas.qml  (Canvas-2D renderer — legacy fallback)
├── shaders/visual.frag
├── visual.qsb          (compiled by build.sh; lives at plugin root, NOT in shaders/)
├── glspectrum.js   (spectrum → texture packing, shared by GL renderer)
├── visuals/*.toml  (equalizer / wave / fire)
├── bin/
│   └── omaviz-engine   (Rust: capture → FFT/DSP → JSON lines on stdout;
│                         COMMITTED artifact — see Architecture A, §2)
└── tests/{model,glspectrum}.test.cjs
```

> **Architecture A (v7):** `plugin/bin/omaviz-engine` is a **committed**,
> self-contained artifact. The plugin directory is a drop-in that installs with
> no build step (`cp -r plugin …/org.omaviz.visualizer/ && omarchy plugin
> enable org.omaviz.visualizer`). `build.sh` rebuilds it from `engine/` source
> and writes the output directly into `plugin/bin/`. `install.sh` copies the
> directory as-is and enables the plugin; it only builds when `--build` is
> passed or the binary is missing.

Data flow:
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
VisualCanvasGL (GPU/ShaderEffect) / VisualCanvas (Canvas-2D) — unchanged contract
```

- **No socket, no daemon, no systemd.** The engine is spawned by the bar widget
  (plugin-relative path, see §3) and lives for the shell session. If it exits,
  the bar's existing `onExited` retry self-heals (same pattern that recovered
  the old bridge across reboots).
- **Lifecycle tradeoff (accepted):** capture stops when the Omarchy shell
  exits/restarts. This is the explicit cost of "no daemon."
- **Backend auto-mapping:** the engine defaults to `--source auto`. In v7.6.0
  only PipeWire is compiled in, so `auto` resolves to PipeWire. Future builds
  add more backends and `auto` probes in priority order (PipeWire → Pulse →
  JACK → ALSA). The plugin **never passes `--source`** — it just spawns the
  binary, staying fully backend-agnostic.
- **Verification-only backends (engine-internal, not for the plugin):** in
  addition to PipeWire, the engine accepts `--source gen` (deterministic
  synthetic signal; sub-mode via `gen=tone|sweep|noise|mixed`, default
  `mixed`), `--source gen=<mode>`, and `--source file=<path>` (loop-replays a
  recorded mono f32 sample file: `.json` array / `.txt` floats / raw `f32`
  LE). These drive the screenshot harness so Bars/Wave/Fire can be verified
  with a reproducible, audio-independent signal. They emit the identical frame
  contract (`source` reported as `"gen"`/`"file"`), and the plugin never uses
  them.

---

## 3. Plugin-relative binary path

Quickshell provides `root.moduleName` on `BarWidget`. Following the proven
pattern from `im0001gt.hw-tooltip`:
```qml
readonly property string engineBin:
  Quickshell.env("HOME") + "/.config/omarchy/plugins/"
  + root.moduleName + "/bin/omaviz-engine"
```
The `Process.command` is `[root.engineBin]`. No absolute `~/.local/bin` path, no
env hacks, no systemd. (Verified against a shipped Omarchy plugin — `hw-tooltip`
resolves `.../scripts/system-usage` the same way.)

The **detached desktop window** (`Desktop.qml`) spawns the same binary via
`Model.engineBin` (the plugin-relative path), passing `--source auto
--bands <density>` where `density` is the desktop window's configured spectrum
resolution (default `128`, valid `32..256`, see §6/§10). This feeds a dense,
immersive spectrum (up to 256 bars) while the mini bar keeps its own 32-band
feed — the engine generalizes `--bands` to any N. The mini's `paused` state is
driven by the BarWidget, not by the desktop window.

---

## 4. Engine contract (bin/omaviz-engine)

CLI:
```
omaviz-engine [--source SRC] [--bands N]

SRC := auto | pipewire | gen[=MODE[:PARAM=V;...]] | file=<path>[:fps=N][:loop]
```
- `--source` default `auto` → PipeWire (default sink monitor). The plugin and
  Detached window always pass `auto`; all other values are for offline/test use.
- `--bands` default `32` (mini bar); the desktop window overrides it with
  `config.density` (default `128`, valid `1..256`, hard cap `256`). Any N is
  accepted — the GL renderer generalizes the bar count (see §10). Must match the
  consumer's expected bar count.
- Synthetic / offline backends (engine lane #11, no QML/shader change):
  - `gen` — built-in deterministic signal generator. Modes:
    - `gen` / `gen=mixed` — multi-partial signal with a pulsing low partial
      (gives Wave/Fire/beat something to track). Params: `pulse=1.5` (Hz),
      `low=120` (Hz).
    - `gen=tone[:freq=440]` — steady sine at `freq` Hz (default 440).
    - `gen=noise` — deterministic pseudo-noise (sum of incommensurate sines).
    - `gen=sweep[:rate=0.2][:min=80][:max=7080]` — 80 Hz↔7080 Hz sine sweep,
      `rate` Hz LFO. No RNG → same invocation always yields the same waveform.
    The generator emits raw audio through the same Analyzer as PipeWire, so the
    output is a real, moving spectrum (verified: tone/sweep/noise are non-silent
    with `source:"gen"`).
  - `file=<path>[:fps=60][:loop]` — replays a recorded spectrum stream. `<path>`
    is the engine's own stdout (one `{"bands":[..],"energy":f,"beat":f,
    "silent":b,"source":".."}` frame per line). The frame is emitted verbatim;
    its `source` is rewritten to `"file"`. At end-of-file the backend sends a
    clean Exit so the engine terminates (unless `loop`, which restarts from the
    top). Used to drive the desktop window with a deterministic synthetic
    spectrum for screenshots.

stdout frame (one JSON object per line, flushed):
```json
{"bands":[0.0, …], "energy":0.0, "beat":0.0, "silent":true, "source":"pipewire"}
```
- `bands`: log-spaced magnitude 0..1 (31/32 values), same shape the QML already
  consumes via `Model.parseSpectrumLine`.
- `energy`/`beat`: smoothed envelope + simple onset detection.
- `silent`: `energy < 0.02`.
- `source`: the resolved backend name (always `"pipewire"` in v7.6.0). Consumed
  by the panel's read-only source display.

The frame is emitted at ~60 Hz regardless of audio chunk rate (the engine
drains the channel, keeps the latest chunk, and ticks on a timer).

---

## 5. Files

Live plugin (`~/.config/omarchy/plugins/org.omaviz.visualizer/`, manifest `2.0.0`):
```
manifest.json (v2.0.0), BarWidget.qml, Panel.qml, Desktop.qml,
Model.js, VisualCanvasGL.qml (GPU/ShaderEffect renderer — default),
VisualCanvas.qml (Canvas-2D legacy fallback),
shaders/visual.frag, visual.qsb (plugin root), glspectrum.js,
visuals/{equalizer,wave,fire}.toml,
bin/omaviz-engine, tests/{model,glspectrum}.test.cjs
```

Engine (`engine/`, Rust source; built by `build.sh` → `plugin/bin/`):
```
Cargo.toml
src/main.rs        (CLI, frame loop, backend resolution)
src/dsp.rs         (Analyzer: Hann-windowed FFT → log bands → envelope/beat)
src/source/mod.rs  (backend registry)
src/source/pipewire.rs (libpipewire capture → mono f32 chunks)
src/frame.rs       (JSON frame builder — unit-tested)
```

Config: shared `~/.config/omaviz/config.toml` (unchanged sections). The plugin
writes it; the engine reads `[audio]` (sensitivity/smoothing/bands). Engine does
**not** need a running systemd daemon to read it.

**Engine binary (`plugin/bin/omaviz-engine`) is committed** (Architecture A) —
it is a tracked artifact, not built at install time. `build.sh` compiles
`engine/` and writes the output into `plugin/bin/`. `install.sh` copies the
whole `plugin/` directory as-is; it only invokes `build.sh` with `--build` or
when the binary is missing.

---

## 6. Settings Panel behavior (v7 deltas)

Unchanged: preview, VISUALIZATION (Bars·Wave), STYLE (Classic·Fire), OPTIONS,
AUDIO (sensitivity/smoothing), Color sync, Reset, Detach.

**New (v7):** AUDIO section shows a read-only line, e.g.
`SOURCE  PipeWire · default sink`. Driven by `Model.spectrumData.source`. No
switching control — the engine auto-detects; the panel only reports.

**GPU toggle (v7.2):** the desktop window honors `desktop.gpu` in the config
TOML. It defaults to `true` (GPU/ShaderEffect renderer, `VisualCanvasGL.qml`);
set `desktop.gpu = false` to fall back to the Canvas-2D `VisualCanvas.qml`.

**Desktop density (v7.6):** the settings panel exposes a **Density** control
(section; `32..128`, step `8`, default `128`) that writes `desktop.density`.
This drives the engine's `--bands` for the detached window and the GL bar count
(see §10). Higher = denser/immersive spectrum; the engine supports up to `256`.

**Wave visual (v7.6):** the VISUALIZATION selector now offers a third value,
**Wave**, for the desktop/full window (mapped to GL visual-code `2`; see §10 and
`ADR/0001-wave-continuous-carrier.md`). Bars / Oscilloscope / Wave are all
shipped GPU modes.

**Wave in the panel selector (T-007 / ADR-0002):** the settings-panel
VISUALIZATION ButtonGroup (`Panel.qml`) now lists **`["Bar", "Oscilloscope",
"Wave"]** (was `["Bar", "Oscilloscope"]`). Exact UI label is **`Wave`** — text
only, no icon, matching `Bar`/`Oscilloscope` (all three are text ButtonGroups; no
iconography is used elsewhere in this group). Selecting `Wave` commits
`visual = "wave"` to **both** `[mini]` and `[desktop]` sections (same commit
pattern as the existing Bar/Oscilloscope handler), so the change applies to the
mini and the detached window. The hand-edited `config.toml` override
(`[desktop] visual = "wave"`) remains valid and is now the same value the panel
writes; `Desktop.qml` already maps `equalizer → Bars`, `oscilloscope →
Oscilloscope`, `wave → Wave` (GL code 2). No engine change — GUI-exposure only.

---

## 7. Detach / desktop window lifecycle (v7.2)

**Toggle button:** the panel footer shows **`Detach ↗`** when the desktop
window is closed and **`Attach ↗`** when it is open. The label is derived from
`desktop.active` (read from the BarWidget's config, the source of truth), so it
flips immediately on click.

**Launch lives on the BarWidget (not the panel):** the launch `Process`
(`detachProc`) is declared on `BarWidget.qml`, which stays loaded whether the
settings panel is open or closed. `Panel.detach()` merely forwards to
`root.hostWidget.detach()`. This avoids the earlier failure where closing the
panel unloaded the panel-local `Process` before it could spawn the window.

**Pause:** while the desktop window is open, the mini freezes (`paused` in
`BarWidget`). `paused` is `Model.isPaused(desktopActive, detachedRunning)` —
it requires **both** the `desktop.active` flag AND the detach process to be
running, so a stale `active=true` left behind by an externally-killed window
does **not** freeze the mini forever.

**Attach (close):** `detachProc.running = false` terminates the child quickshell
directly (the Process uses the `environment` property, not an `env` wrapper, so
the child is the direct descendant). `onExited` then clears `detachedRunning`
and resets `desktop.active=false`.

**Resilience (v7.2 fixes):**
- The Attach branch resets `desktop.active=false` **unconditionally**, not only
  via `onExited`. If the window died without firing `onExited` (external kill /
  crash), the flag would otherwise stay stuck `true` and the button would freeze
  on "Attach" with no window to close.
- **Self-heal on config load:** `BarWidget`'s config `FileView.onLoaded` resets
  `desktop.active` to `false` when it is `true` but no detach window is running,
  so a crash can never leave the button permanently stuck.

Engine: the desktop window runs its **own** engine instance (`--bands 32`); the
bar keeps its own. Both feed their respective visualizers independently.

---

## 8. Rendering — `VisualCanvasGL.qml` (GPU, default) + `VisualCanvas.qml` (Canvas-2D fallback)

Primary rendering is the GPU/ShaderEffect path (`VisualCanvasGL.qml` +
`shaders/visual.frag` → `visual.qsb` at the plugin root — see §10). `VisualCanvas.qml`
is the self-contained Canvas-2D legacy fallback (modes: Bars, Wave, Fire winamp
flame; `barCount` downsamples the 32-band spectrum; `colourScheme`/`colorSync`
drive color). Both honor the same rendering contract consumed by the bar/desktop
widgets — switching between them never changes the upstream data shape. Note: the
Canvas-2D "Wave" style is **unrelated** to the GL **WAVE** visual defined in §10 /
ADR-001; the GL WAVE mode is a continuous-ribbon GPU effect, not the Canvas-2D wave.

---

## 9. Testing (TDD — source of truth for "works")

**Engine (Rust, `cargo test` in `engine/`):** 34 tests green (verified 2026-08-19: `test result: ok. 34 passed; 0 failed`).
`dsp.rs` (band count, silence→zero energy, tone→non-silent, short-buffer ring
handling), `frame.rs` (JSON build/parse), `source/mod.rs` (auto/pipewire
resolution), `source/gen.rs` (synthetic generator modes), `source/file.rs`
(offline replay). Reviewer confirmed the suite green (2026-08-19); run
`cargo test` to re-confirm the exact count locally (≈34 `#[test]`/test-fn
blocks across the modules above).
- `dsp.rs`: ported from the v6 daemon — band count, silence→zero energy,
  tone→non-silent, short-buffer ring handling. Carry these forward.
- `frame.rs`: `build_frame(bands, energy, beat, silent, source)` → JSON string
  with the exact v7 key set/order; parseable; numeric precision stable.
- source resolution: `auto`/`pipewire`/`""` → `pipewire`; unknown → error.

**Plugin (node, `node plugin/tests/model.test.cjs`):** 55 tests green (verified 2026-08-19: exit 0, fail 0; incl. the v7.6 desktop-density assertion: `density` drives the dense GL spectrum independently of `audio.bands`, default `128`).
- Carry forward all v6 Model.js tests (TOML read/write, visual discovery,
  spectrum parse, pause cycle, color sync, style round-trip).
- `parseSpectrumLine` captures `source` into `spectrumData.source`; panel
  source-display string derives from it.
- `isPaused(desktopActive, detachRunning)` — two-signal pause resolution.
- `defaultConfig.gpu` is `true`; `readConfigFromText` honors `desktop.gpu`.

**GPU packing (node, `node plugin/tests/glspectrum.test.cjs`):** 17 tests green (verified 2026-08-19: `ℹ pass 17`, `ℹ fail 0`).
- `packBands(bands, n)` downsamples/upsamples the variable-length spectrum to a
  fixed `n=32` slot array and clamps out-of-range values so a bad frame can
  never poison the shader; empty/undefined → all zeros.
- `peakOf(packed)` returns the max packed value (drives glow/beat in the shader).
- `packFire(fire)` → `1.0`/`0.0` for control-texture row 8; `fireOn(v)` mirrors
  `visual.frag`'s decoder (`row8.r > 0.5 == on`). **Decode note (v7.5 fix):** the
  shader now reads toggles with `> 0.5` (the old `int(r*2+0.5)==1` wrongly read
  the painted `1.0` as `2`, leaving fire/peaks permanently off).
- **Decode note (v7.6 fix):** the visual selector (row 2 R) is packed **RAW**
  `0/1/2` (Bars/Oscilloscope/Wave) and the shader decodes with
  `int(ctrl().r*255.0+0.5)`. The earlier `*2` scheme mapped `2`→`1`, so the WAVE
  branch never fired. Additionally the control texture (`specTex`) must be
  sampled with **NEAREST** filtering — the default `Linear` averaged the
  packed `2/255` with the animated time row, again decoding WAVE as
  Oscilloscope. **In Qt 6 the `ShaderEffectSource.filtering` property does
  not exist (see ADR-0005)**, so NEAREST is forced via
  `specCanvas.layer.enabled: true; specCanvas.layer.smooth: false` on the
  `ShaderEffectSource.sourceItem` (the only QML-facing mechanism). Covered by
  `glspectrum.test.cjs` (`visual decode rides raw 0/1/2…`, `control texture
  uses NEAREST via sourceItem.layer.smooth:false…`).
- **Density generalization (v7.6):** `packBands(bands, density)` downsamples/
  upsamples the variable-length spectrum to the fixed `density` length and clamps
  out-of-range values; `packGap(gap)` mirrors the QML `barGap` paint
  (`clamp(0..1)*255`). The shader reads `NB` from row 11 R (`nbVal()`) and
  `barGap` from row 11 G — no free-standing uniform (qsb/Vulkan rejects those).

**Integration (manual, gated):**
- After install: spawn engine standalone with a 440 Hz tone playing → confirm
  non-silent JSON frames with spectral peak. (No live playback in CI; done
  manually on the host.)
- Detach/Attach: click Detach → desktop window opens + its own engine spawns;
  click Attach (or close window) → window closes, `desktop.active` resets to
  false, mini resumes.
- GPU path: with `desktop.gpu` unset/true the desktop window renders via
  `VisualCanvasGL.qml` (ShaderEffect); setting `desktop.gpu=false` falls back to
  Canvas-2D `VisualCanvas.qml`.

---

## 10. GPU / ShaderEffect rendering (current implementation)

The engine is **orthogonal to rendering**. Since v7.2 the live plugin renders
with a QML `ShaderEffect` (GLSL) inside the scene graph — **no separate EGL
context** — which avoids the historical wgpu+Mesa segfault that forced the old
daemon to leak its `App` on exit.

The renderer is a scene-graph `ShaderEffect` (not a spawned wgpu surface), so it
does not carry the historical wgpu+Mesa segfault risk. However, **verifying it
live requires explicit per-capture USER pre-approval** — no agent may deploy via
`install.sh` or launch/capture a GPU/Wayland surface on its own authority. The
old "agents must not launch the window" guardrail is REAFFIRMED under
`AGENT_GOVERNANCE.md` (GPU launch rule); the prior "safe to verify live / agents
MAY capture" language in `GOVERNANCE.md` v1 is revoked. Static gates (cargo test,
node suites, qmllint) remain the primary acceptance bar; a live capture is only
performed when the user explicitly authorizes it.

**Files (this track):**
- `VisualCanvasGL.qml` — the GPU renderer. It packs the live `bands` array plus
  control values (visual mode, color source, fire/peaks/border toggles, falloff,
  alpha, theme/custom colors, time) into a `density×12` RGBA `Canvas` (desktop
  window defaults to `density=128`; the mini preview uses fewer), promotes that
  to a `ShaderEffectSource`, and runs `visual.qsb` as the `ShaderEffect`
  fragment shader. `glspectrum.js` (`packBands`/`peakOf`/`packGap`) clamps and
  generalizes the variable-length `bands` array into the fixed `density`-slot
  texture row so a bad frame can never poison the shader. GPU is **enabled by
  default** (`Model` reads `desktop.gpu`; it is `true` unless explicitly
  `"false"`).
- `shaders/visual.frag` — GLSL ES 3.10 fragment shader, compiled to
  `visual.qsb` by `build.sh`. Data is read from the `density×12` texture rows
  (row 0 = spectrum magnitudes, row 1 = JS-maintained peak-hold, rows 2–11 =
  control/color/time uniforms). The shader dispatches three visual modes (Bar /
  Oscilloscope / Wave; see §10 + `ADR/0001-wave-continuous-carrier.md`). Visuals
  are **flat 2D** (no 3D, product direction) and bar colors are sourced from the
  active Omarchy theme per `THEME_PALETTE.md` (defaults seeded to Matte Black
  `#e68e0d`→`#f59e0b`).
- `VisualCanvas.qml` — **legacy Canvas-2D fallback**, retained only for
  non-GPU/debug use. It is not the default path.

**How shaders map to visuals (v7.6 — three visualizations, per product direction):**
the visual is selected by a control row (`R` channel of row 2), packed **RAW** as
`0`/`1`/`2` — the shader decodes with `int(ctrl().r*255.0+0.5)` so the three
codes stay distinct (the old `*2` scheme collided `2`→`1`). A
`visuals/<name>.toml` enumerates the available modes so the panel dropdown stays
in sync. Mapping onto the single shared shader (see
`ADR/0001-wave-continuous-carrier.md` for the WAVE rationale):
- **Bar** (priority visual) → analyzer branch (`visual` control row = `0`):
  Winamp-style 2D spectrum bars, themed gradient (active Omarchy accent ramp,
  `THEME_PALETTE.md`) or custom color. The **fire** option is a *Bar effect* —
  a 2D fluid/drip flame post-process over the bars (`fireOn()` flag, row 8),
  render-only, no engine change. (The legacy `visuals/fire.toml` toggles this
  effect rather than defining a separate visual.)
- **Oscilloscope** → oscilloscope branch (`visual` control row = `1`): an animated
  sine envelope driven by the spectrum. Derives from the same `bands` frame (no
  engine mode field). **Line width (T-009 / ADR-0004):** the branch historically
  read `alphaRow().g * 0.02` to set stroke width, but row 10 G is **never packed**
  (VisualCanvasGL.qml packs `row(10, alpha*255, 0, 0)` — G/B/A are `0`), so the
  term reduced to a constant `0.004` floor and the input was dead. Per ADR-0004 the
  `*0.02` dead term is removed: oscilloscope line width is the fixed `0.004`
  constant. `width` is intentionally not a user knob (the spectrum `density` and
  `peaks` already control line detail). Row 10 is now **reserved** (only `R` =
  `alpha` is used; G/B/A are reserved, not "unused-and-read").
- **Wave** (v7.6, `visual` control row = `2`): a field of **continuous woven
  ribbons** rendered in a bounded loop (`const int NW = 24` — GLSL ES-3.10 safe).
  The ribbon geometry (per-ribbon `freq = 4.0 + depth*9.0`, `phase` from
  `meta().r`, carrier amplitude `0.13`, envelope swing `env*0.55*react`) is
  **computed in-shader from `depth` + the time uniform `meta().r`, not from
  `visuals/wave.toml` params** — see ADR-0001 (continuous-carrier decision) and
  ADR-0003 (wave.toml params are deliberate no-ops, trimmed from the panel). This
  keeps every ribbon a continuous line at all loudness levels.
  Each ribbon is an *always-visible continuous sine carrier* (`carrier * 0.13`,
  independent of loudness) so the lines are never broken into dots; the spectrum
  adds an *additive swing* (`+ env * 0.55 * react`) on top, so music modulates
  the ribbons without ever collapsing them. Design decision: music "flexes" the
  lines, it never breaks them (see `ADR/0001-wave-continuous-carrier.md`).
`fire`/`peaks`/`border`/`alpha`/`falloff` and the `colorSource` (theme vs
custom) are passed as texture control rows and consumed in `visual.frag`. All
three visuals share the one compiled shader rather than separate shader files.
Open follow-ups are tracked as ADRs: ADR-0002 (expose Wave in the panel
selector), ADR-0003 (trim inert `visuals/wave.toml` params), ADR-0004
(oscilloscope line-width dead input + reserved alpha row 10).

**Dynamic bar count + gaps (v7.6):** the bar count (`NB`) is dynamic and rides
in control-texture **row 11 R** as `density/256.0` (`nbVal()` in the shader,
hard cap `256`), so the desktop window renders a dense spectrum (e.g. `128`
bars, `barGap = 0` = contiguous/immersive) while the mini keeps its 32-band
feed — no free-standing uniform (qsb/Vulkan rejects those in a ShaderEffect).
`barGap` rides in row 11 G (`0` = contiguous dense, `~0.10` = slim gaps, mini
default). The control texture is sampled with **NEAREST** filtering (forced in
Qt 6 via `specCanvas.layer.enabled: true; specCanvas.layer.smooth: false` on the
`ShaderEffectSource.sourceItem` — `ShaderEffectSource.filtering` does not exist
in Qt 6; see ADR-0005) so packed codes (visual `0/1/2`, toggles, density) are
not averaged with neighbouring rows — without it, visual-code `2` decoded as `1`
and Wave silently rendered as the Oscilloscope branch. `packBands` generalizes the
variable-length `bands` array to the fixed `density` length (clamps out-of-range
so a bad frame can never poison the shader); `packGap` mirrors the QML paint.

This track touches only QML/GLSL; the engine (audio) is unaffected.

---

## 11. Operational notes

- Edit the **repo** first, then copy changed files into the live plugin dir to
  test. Never edit the live copy directly.
- v7 has **no** `systemctl --user status omaviz.service` and **no**
  `/run/user/1000/omaviz.sock`. If the mini is dead, check: (1) the bar spawned
  `bin/omaviz-engine` (process exists), (2) the plugin is **enabled**
  (`omarchy plugin list` shows `enabled` — a freshly copied plugin is `disabled`
  by default and must be enabled), (3) PipeWire is running and playing audio,
  (4) `~/.config/omaviz/config.toml` is valid TOML.
- Install: `./install.sh` copies `plugin/` → live dir, then `omarchy plugin
  enable org.omaviz.visualizer` + restart. Zero-build by default (the committed
  binary ships inside `plugin/bin`). Use `./install.sh --build` to rebuild the
  engine from `engine/` first. `./build.sh` alone rebuilds the binary into
  `plugin/bin/` (and recompiles `shaders/visual.frag` → `visual.qsb` (plugin root)).
  Uninstall: `./uninstall.sh` (removes plugin + bin; no systemd step).
- Because the engine binary is committed, the plugin directory is a true
  drop-in: `cp -r plugin ~/.config/omarchy/plugins/org.omaviz.visualizer/ &&
  omarchy plugin enable org.omaviz.visualizer` is sufficient.

---

## 12. Repository structure

```
omaviz/                  (this repo, tag v7.6)
├── APPLICATION_SPEC.md  (this file)
├── engine/              (Rust omaviz-engine source — build.sh compiles → plugin/bin)
│   ├── Cargo.toml
│   └── src/{main,dsp,frame}.rs, src/source/{mod,pipewire}.rs
├── plugin/              (QML/JS — copied verbatim to live dir; bin/ is committed)
│   ├── manifest.json (v2.0.0), BarWidget.qml, Panel.qml, Desktop.qml
│   ├── Model.js, VisualCanvasGL.qml (GPU renderer), VisualCanvas.qml (Canvas-2D fallback)
│   ├── shaders/visual.frag
│   ├── visual.qsb (compiled by build.sh → plugin root, not under shaders/)
│   ├── glspectrum.js
│   ├── visuals/{equalizer,wave,fire}.toml
│   ├── bin/omaviz-engine   (COMMITTED engine binary — Architecture A)
│   └── tests/{model,glspectrum}.test.cjs
├── build.sh             (cargo build → plugin/bin/omaviz-engine; compiles shaders)
├── install.sh           (copy plugin dir + omarchy plugin enable; zero-build)
├── uninstall.sh         (remove plugin; no systemd)
└── v6/                  (ARCHIVE: prior daemon+bridge+socket design)
```

**Caveats:**
- `v6/` is the historical multi-process implementation, kept for reference. Do
  not resurrect its daemon/socket; v7 supersedes it.
- `plugin/bin/omaviz-engine` is a **committed** artifact (Architecture A), not a
  build-time output. Rebuild it with `build.sh` after changing `engine/` source;
  `install.sh` uses the committed copy unless `--build` is given.

---

## 13. Feature roadmap

Progress reflects shipped capability in the live plugin (tag `v7.6`).

| # | Feature | Status | Progress |
|---|---------|--------|---------:|
| 1 | Single-package plugin (QML + bundled native engine, no systemd/socket) | Shipped | 100% |
| 2 | Zero-build drop-in install (committed binary, `omarchy plugin enable`) | Shipped | 100% |
| 3 | PipeWire audio capture → 32-band spectrum (default sink monitor) | Shipped | 100% |
| 4 | Mini bar visualizer (Bars / Wave / Fire) | Shipped | 100% |
| 5 | Settings panel (visualization, style, audio, color sync, reset) | Shipped | 100% |
| 6 | Read-only audio source indicator (PipeWire) | Shipped | 100% |
| 7 | Desktop detach window (standalone spectrum window) | Shipped | 100% |
| 8 | Detach/Attach toggle with mini pause + stale-flag resilience | Shipped | 100% |
| 9 | TDD: engine (Rust) + plugin (node) + gl-spectrum test suites green | Shipped | 100% |
| 10 | Additional backends (PulseAudio / JACK / ALSA) | Planned | 0% |
| 11 | File/loopback source for offline testing (`gen`/`file` engine backends, lane #11) | Shipped | 100% |
| 12 | GPU / ShaderEffect Winamp visuals (Bars + Oscilloscope + **Wave**, dense desktop spectrum via dynamic `--bands`, fire effect, omarchy-themed) | Shipped | 100% |
| 13 | Backend-switching UI (manual source selection) | Planned | 0% |
| 14 | Multi-monitor / position presets for detach window | Backlog | 0% |
| 15 | Preset/theme sharing for visuals | Backlog | 0% |
| 16 | Expose **Wave** in the settings-panel VISUALIZATION selector (was Bar/Oscilloscope only) — UI label "Wave", commits `visual="wave"` to `[mini]`+`[desktop]` | Shipped | 100% | (spec: ADR-0002) |
| 17 | `visuals/wave.toml` params (amplitude/frequency/brightness/peak_fall) trimmed — inert in the continuous-carrier WAVE shader (decision: trim, not wire) | Shipped | 100% | (spec: ADR-0003) |
| 18 | Oscilloscope line-width dead input removed; control-texture row 10 G/B/A marked reserved (was falsely documented "unused") (P3) | Shipped | 100% | (spec: ADR-0004) |
| 19 | Control-texture NEAREST filtering (T-013): `ShaderEffectSource.Nearest` is invalid in Qt 6; force NEAREST via `sourceItem.layer.smooth:false`. Fixes WAVE decoding to Oscilloscope under LINEAR. | In Progress | 0% | (spec: ADR-0005) |
| 20 | Settings-panel popup invisible (T-014): surface anchored to injected `anchorItem`/`owner`; `open` re-emitted from base `panelController`; re-anchor on injection. Shell-layer (not GPU). | Backlog | 0% | (spec: ADR-0008) |
| 21 | Detached desktop window blank + no audio (T-015): per-instance PipeWire node name so the 2nd engine captures; surface engine stderr; push bands per-frame (not one-shot Binding). | Backlog | 0% | (spec: ADR-0009) |
| 22 | Click mapping left vs right (T-016): **BLOCKED pending user confirmation** — current mapping left=settings/right=detach stands as default; relayed expectation (left=detach) is *unverified*, needs explicit user statement. No UX change until decided. | Backlog | 0% | (spec: ADR-0010) |
