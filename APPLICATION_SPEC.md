# omaviz — Application Specification (v7.0.0)

> **Plugin id:** `org.omaviz.visualizer`
> **Version:** 7.0.0 (manifest) · repo tag `v7`
> **Status:** Single-package Omarchy QML plugin. Audio analysis is bundled as
> one native binary (`engine/omaviz-engine`) shipped **inside** the plugin
> directory. No systemd service, no Unix socket, no `~/.local/bin` binaries.

This document is the **source of truth** for what v7 ships and how it is verified.
The prior multi-process design (daemon + socket + bridge) is archived in `v6/`.

---

## 1. Goals & Non-Goals

**Goals**
- React to system playback audio (not microphone) via the default audio sink.
- Ship as a **single plugin directory** — every dependency (QML, JS, native
  engine binary) lives under `~/.config/omarchy/plugins/org.omaviz.visualizer/`.
- Support **multiple audio backends** behind an auto-detected source mapping.
  v7.0.0 ships **PipeWire only**; PulseAudio/JACK/ALSA/File follow later with
  **no plugin (QML) changes** — the plugin never picks a backend.
- Keep the existing UI: bar mini, desktop detach, settings panel, Canvas-2D
  visuals (Bars/Wave/Fire-style). The audio plumbing changes; the product does not.
- Show the active audio source in the settings panel (read-only).

**Non-Goals (v7.0.0)**
- No GPU/WGSL/ShaderEffect rendering yet (planned, separate track — §10).
- No microphone monitoring.
- No backend switching UI (source is auto + displayed, not chosen).

---

## 2. Architecture (v7 — single package)

```
plugin/  (deployed to ~/.config/omarchy/plugins/org.omaviz.visualizer/)
├── manifest.json
├── BarWidget.qml   (spawns bin/omaviz-engine, parses its stdout)
├── Panel.qml       (settings: shows Source: <backend> in AUDIO section)
├── Desktop.qml     (detached window)
├── Model.js        (.pragma singleton: config IO, spectrum parse)
├── VisualCanvas.qml (Canvas-2D renderer)
├── visuals/*.toml  (equalizer / wave / fire)
├── bin/
│   └── omaviz-engine   (Rust: capture → FFT/DSP → JSON lines on stdout)
└── tests/model.test.cjs
```

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
VisualCanvas / bars (unchanged rendering contract)
```

- **No socket, no daemon, no systemd.** The engine is spawned by the bar widget
  (plugin-relative path, see §3) and lives for the shell session. If it exits,
  the bar's existing `onExited` retry self-heals (same pattern that recovered
  the old bridge across reboots).
- **Lifecycle tradeoff (accepted):** capture stops when the Omarchy shell
  exits/restarts. This is the explicit cost of "no daemon."
- **Backend auto-mapping:** the engine defaults to `--source auto`. In v7.0.0
  only PipeWire is compiled in, so `auto` resolves to PipeWire. Future builds
  add more backends and `auto` probes in priority order (PipeWire → Pulse →
  JACK → ALSA). The plugin **never passes `--source`** — it just spawns the
  binary, staying fully backend-agnostic.

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

---

## 4. Engine contract (bin/omaviz-engine)

CLI:
```
omaviz-engine [--source auto|pipewire] [--bands N]
```
- `--source` default `auto`. v7.0.0 accepts `auto`/`pipewire` only.
- `--bands` default `32`; must match the bar's `config.bands`.

stdout frame (one JSON object per line, flushed):
```json
{"bands":[0.0, …], "energy":0.0, "beat":0.0, "silent":true, "source":"pipewire"}
```
- `bands`: log-spaced magnitude 0..1 (31/32 values), same shape the QML already
  consumes via `Model.parseSpectrumLine`.
- `energy`/`beat`: smoothed envelope + simple onset detection.
- `silent`: `energy < 0.02`.
- `source`: the resolved backend name (always `"pipewire"` in v7.0.0). Consumed
  by the panel's read-only source display.

The frame is emitted at ~60 Hz regardless of audio chunk rate (the engine
drains the channel, keeps the latest chunk, and ticks on a timer).

---

## 5. Files

Live plugin (`~/.config/omarchy/plugins/org.omaviz.visualizer/`):
```
manifest.json, BarWidget.qml, Panel.qml, Desktop.qml,
Model.js, VisualCanvas.qml, visuals/{equalizer,wave,fire}.toml,
bin/omaviz-engine, tests/model.test.cjs
```

Engine (`engine/`, built at install time → copied to `plugin/bin/`):
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

---

## 6. Settings Panel behavior (v7 deltas)

Unchanged: preview, VISUALIZATION (Bars·Wave), STYLE (Classic·Fire), OPTIONS,
AUDIO (sensitivity/smoothing), Color sync, Reset, Detach.

**New (v7):** AUDIO section shows a read-only line, e.g.
`SOURCE  PipeWire · default sink`. Driven by `Model.spectrumData.source`. No
switching control — the engine auto-detects; the panel only reports.

---

## 7. Detach / desktop window lifecycle — unchanged (verified).

Detach writes `desktop.active=true` (mini pauses) + launches `Desktop.qml`.
On close, `desktop.active=false` → mini resumes. Engine keeps running for both.

---

## 8. Rendering (`VisualCanvas.qml`) — unchanged (verified).

Self-contained Canvas-2D. Modes: Bars, Wave, Fire (winamp flame). `barCount`
downsamples the 32-band spectrum; `colourScheme`/`colorSync` drive color.

---

## 9. Testing (TDD — source of truth for "works")

**Engine (Rust, `cargo test` in `engine/`):**
- `dsp.rs`: ported from the v6 daemon — band count, silence→zero energy,
  tone→non-silent, short-buffer ring handling. Carry these forward.
- `frame.rs`: `build_frame(bands, energy, beat, silent, source)` → JSON string
  with the exact v7 key set/order; parseable; numeric precision stable.
- source resolution: `auto`/`pipewire`/`""` → `pipewire`; unknown → error.

**Plugin (node, `node plugin/tests/model.test.cjs`):**
- Carry forward all v6 Model.js tests (TOML read/write, visual discovery,
  spectrum parse, pause cycle, color sync, style round-trip).
- **New:** `parseSpectrumLine` captures `source` into `spectrumData.source`;
  panel source-display string derives from it.

**Integration (manual, gated):**
- After install: spawn engine standalone with a 440 Hz tone playing → confirm
  non-silent JSON frames with spectral peak. (No live playback in CI; done
  manually on the host.)

---

## 10. Migration path → GPU / ShaderEffect (future, separate track)

The engine is **orthogonal to rendering**. To move from rectangles to Winamp-
style GPU visuals, change only the render side:
- Port `VisualCanvas.qml` from Canvas-2D to a QML `ShaderEffect` (GLSL) inside
  the scene graph (no separate EGL context → avoids the historical wgpu+Mesa
  segfault that forced the daemon to leak its `App` on exit). Feed `bands` as a
  `uniform` array or a 1-D `Texture`.
- Each Winamp visual = one `visuals/<name>.toml` + one fragment shader. Roll
  them out one by one (Bars → Wave → Fire → …). The panel dropdown already
  enumerates `*.toml`, so new visuals appear automatically.

This track touches only QML/GLSL; the engine (audio) is unaffected.

---

## 11. Operational notes

- Edit the **repo** first, then copy changed files into the live plugin dir to
  test. Never edit the live copy directly.
- v7 has **no** `systemctl --user status omaviz.service` and **no**
  `/run/user/1000/omaviz.sock`. If the mini is dead, check: (1) the bar spawned
  `bin/omaviz-engine` (process exists), (2) PipeWire is running and playing
  audio, (3) `~/.config/omaviz/config.toml` is valid TOML.
- Install: `./install.sh` builds `engine/` → `plugin/bin/omaviz-engine`, copies
  the plugin, enables it. Uninstall: `./uninstall.sh` (removes plugin + bin; no
  systemd step).

---

## 12. Repository structure

```
omaviz/                  (this repo, tag v7)
├── APPLICATION_SPEC.md  (this file)
├── engine/              (Rust omaviz-engine — bundled into plugin/bin)
│   ├── Cargo.toml
│   └── src/{main,dsp,frame}.rs, src/source/{mod,pipewire}.rs
├── plugin/              (QML/JS — copied verbatim to live dir; bin/ added at build)
│   ├── manifest.json, BarWidget.qml, Panel.qml, Desktop.qml
│   ├── Model.js, VisualCanvas.qml
│   ├── visuals/{equalizer,wave,fire}.toml
│   └── tests/model.test.cjs
├── install.sh           (build engine → plugin/bin, install plugin; no systemd)
├── uninstall.sh         (remove plugin; no systemd)
└── v6/                  (ARCHIVE: prior daemon+bridge+socket design)
```

**Caveats:**
- `v6/` is the historical multi-process implementation, kept for reference. Do
  not resurrect its daemon/socket; v7 supersedes it.
- Prebuilt `plugin/bin/omaviz-engine` safety copy: committed after the first
  successful `cargo build` (mirrors v6's binary-safety-copy practice).
