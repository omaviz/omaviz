# omaviz — Application Specification (current implementation)

> **Plugin id:** `org.omaviz.visualizer`
> **Version:** 2.0.0 (manifest) · code line `v5` (2026-08-16)
> **Status:** Omarchy QML plugin for the UI, backed by **two external Rust
> binaries** (`omaviz` daemon + `omaviz-spectrum-bridge`) that are NOT part of
> the plugin. The plugin QML/JS is self-contained; the audio analysis is not.

This document is the **source of truth** for what is shipped and verified. The
earlier Rust/WGSL design notes live in `omaviz-v2-spec.md` (original proposal,
now historical). The GPU/WGSL migration path is kept as a forward-looking
section (§10).

---

## 1. Goals & Non-Goals

**Goals**
- React to system playback audio (not the microphone).
- Live in the Omarchy bar as a mini stacked-rectangle visualizer.
- Optional detached **desktop window** (~600×200) for a larger view.
- A settings panel (on click) to switch visualization + style, tweak knobs, and
  toggle color sync — no rebuild needed.
- Stay out of the way; the mini is always present, the desktop only on demand.

**Non-Goals (current)**
- No GPU/WGSL rendering yet — visuals are Canvas-2D in `VisualCanvas.qml`.
- No microphone monitoring.
- No egui/GTK settings window for the plugin — the panel is QML.

---

## 2. Architecture (REAL — corrected)

```
                ┌──────── PipeWire (sink monitor) ────────┐
                ▼                                          │
   ┌──────────────────────── omaviz DAEMON (Rust, ~/.local/bin/omaviz) ─────────────────────┐
   │  capture (PipeWire) → FFT/DSP → OMAV frames → broadcasts over /run/user/1000/omaviz.sock │
   └───────────────────────────────────────────────────────────────────────────────────────────┘
                │  unix socket (omaviz.sock)
                ▼
   ┌──────────────── omaviz-spectrum-bridge (Rust, ~/.local/bin) ─────────────────┐
   │  connects to omaviz.sock, reads OMAV frames, prints JSON spectrum lines:      │
   │  {"bands":[…32 values…], "energy":<f>, "beat":<f>}  (one JSON object/line)    │
   └────────────────────────────────────────────────────────────────────────────────┘
                │  JSON lines on stdout
                ▼
   ┌────────────────────── omarchy-shell (one Quickshell process) ─────────────────────┐
   │  BarWidget.qml  (bar-widget, always present)                                      │
   │   ├─ stacked Rectangle bars (mini mode)                                           │
   │   ├─ spectrumProc (Process) spawns omaviz-spectrum-bridge, parses stdout lines    │
   │   │   via Model.parseSpectrumLine → Model.spectrumData (bands/energy/beat/silent) │
   │   ├─ left-click → open() the panel; desktop.active=true → render dimmed/paused    │
   │   └─ Loader → Panel.qml (settings UI, loaded in-process)                          │
   │  Panel.qml  (settings): preview, dropdowns, knobs, audio, color-sync, footer      │
   │  Model.js   (shared logic): frames, config IO, visual discovery                   │
   │  VisualCanvas.qml (Canvas-2D renderer, no shell-only imports)                     │
   └───────────────────────────────────────────────────────────────────────────────────┘
```

- **Two external binaries, not in the plugin.** The plugin folder contains only
  QML/JS. `BarWidget.spectrumProc` launches `omaviz-spectrum-bridge` by absolute
  path (`/home/kishan/.local/bin/omaviz-spectrum-bridge`). The bridge in turn
  depends on the `omaviz` daemon (which creates `omaviz.sock`). The daemon is a
  **systemd user service** (`~/.config/systemd/user/omaviz.service`,
  `WantedBy=default.target`, `Linger=yes`) so it auto-starts on boot.
- **Frames:** bridge → JSON lines on stdout → `SplitParser` in `BarWidget.qml`
  → `Model.parseSpectrumLine` → `Model.spectrumData`. The bar reads
  `spectrumData.bands`. Shape: `{ bands: number[32], energy: f32, beat: f32 }`.
- **Config:** shared `~/.config/omaviz/config.toml` (also read by the daemon for
  `audio.*`). The panel reads/writes it through `Model.js`; the bar keeps its own
  watching `FileView` so detach-close → resume propagates cross-process.

### Why this matters operationally
If the `omaviz` daemon is down, `omaviz.sock` is never created, the bridge's
`connect()` fails with `ENOENT`, and **no data reaches the bar** — the mini
renders dimmed/empty. (This is what happened when `config.toml` had invalid TOML
and the daemon crashed on startup.) The daemon + bridge binaries are currently
deployed at `~/.local/bin/` but their **source was not in the plugin repo** — see
§12 (Repository structure) for the recovery status.

---

## 3. Files

Live plugin (`~/.config/omarchy/plugins/org.omaviz.visualizer/`):
```
├── manifest.json          # Plugin contract (bar-widget kind)
├── BarWidget.qml          # bar-widget entry (mini); loads Panel via Loader; spawns bridge
├── Panel.qml              # settings panel (preview, dropdowns, knobs, detach)
├── Desktop.qml            # detached 600×200 window (Quickshell, launched on Detach)
├── Model.js               # logic: frames, config IO, visual discovery (.pragma library)
├── VisualCanvas.qml       # self-contained Canvas-2D renderer (Bars/Wave/Fire-style)
└── visuals/
    ├── equalizer.toml      # label "Bars"
    ├── wave.toml           # label "Wave"
    └── fire.toml           # label "Fire" (style params)
```

`tests/model.test.cjs` — 35 node tests for `Model.js` (`node tests/model.test.cjs`).

---

## 4. Visualizations & the Fire-is-a-Style model
*(unchanged from prior spec — verified behavior)*

- **Visualizations:** `Bars` (equalizer.toml) and `Wave` (wave.toml) — the
  VISUALIZATION dropdown entries.
- **Styles:** `Classic` and `Fire`. **Fire is a STYLE of the Bars visual**, not a
  separate visualization. Selected in the STYLE dropdown. When style=Fire and
  visual=Bars, the panel shows Bars knobs **plus** Fire knobs. `VisualCanvas.qml`
  renders the winamp-style flame when `style==="fire"`.
- Visuals/params are data-driven from `visuals/<name>.toml`.

---

## 5. Configuration (`~/.config/omaviz/config.toml`)
*(unchanged — verified)*

Sections: `[audio]` (sensitivity/smoothing/bands), `[mini]`/`[desktop]`/`[full]`
(visual/style/color_sync/active/…), `[visual.<name>]` (per-param overrides),
`[palette]` (legacy, unused by QML).

**Write model:** the panel keeps an authoritative in-memory `configText` buffer;
`writeConfigKey` mutates it synchronously; `configWrite` (`FileView`,
`watchChanges:false`) only persists. This avoids the 2-click regression.

---

## 6. Settings Panel behavior
*(unchanged — verified)*

Preview, VISUALIZATION (Bars·Wave), STYLE (Classic·Fire), OPTIONS (dynamic knobs
+ Fire knobs), AUDIO (sensitivity/smoothing), Color sync toggle, Reset, Detach.
Labels: ALL-CAPS section headers only; the Visualization/Style dropdown inline
labels were dropped, other field labels kept.

---

## 7. Detach / desktop window lifecycle
*(unchanged — verified)*

Detach writes `desktop.active=true` (mini pauses) + launches `Desktop.qml` via
`detachProc`. Re-launch fix: `StdioCollector` + forced re-spawn +
`onExited` safety net so the mini is never left stuck paused. On close,
`desktop.active=false` → mini resumes.

---

## 8. Rendering (`VisualCanvas.qml`)
*(unchanged — verified)*

Self-contained Canvas-2D. Modes: Bars, Wave, Fire (winamp flame). `barCount`
downsamples the 32-band spectrum; `colourScheme` / `colorSync` drive color.

---

## 9. Testing
*(unchanged)*

`tests/model.test.cjs` — 35 node tests. QML-runtime behaviors verified via
runtime logs (`qs log`), not screenshots (the panel is a Quickshell layer not
captured by window/screen tools).

---

## 10. Migration path → GPU / WGSL (future)
*(unchanged forward-looking section — see prior spec §10)*

Keep the data contract (`Model.spectrumData`, `visuals/<name>.toml`); swap only
the renderer; promote `visuals/*.wgsl` from placeholder to real shaders. Risk:
GPU teardown on Wayland (the historical daemon leaked its `App` on exit to dodge
a wgpu+Mesa EGL segfault) — any GPU migration must keep that discipline.

---

## 11. Operational notes
*(updated)*

- Edit the **repo** (`~/workspace/omaviz`) first, then copy changed files into
  the live plugin dir to test. Never edit the live copy directly.
- The audio pipeline is **three processes**: PipeWire → `omaviz` daemon
  (`omaviz.sock`) → `omaviz-spectrum-bridge` → bar. The daemon is a systemd
  user service; the bridge is spawned per-bar. If the mini is dead after a
  reboot, check `systemctl --user status omaviz.service` and
  `/run/user/1000/omaviz.sock` first.
- `desktop.active` must be `"false"` for the mini to render.

---

## 12. Repository structure & dependency recovery

The plugin repo was historically **rewritten to be QML-only** (commits after
`8ce67a3`), dropping the Rust `src/`. The two external binaries are therefore
**not buildable from the current `master`**. Recovery status as of `v5`:

```
omaviz/                      (this repo)
├── daemon/                  ← RECOVERED from tag v0.2.0 (last commit with full Rust src)
│   ├── Cargo.toml           (omaviz 0.1.0; deps: pipewire, realfft, wgpu, egui, winit, …)
│   ├── src/                 (capture, dsp, ipc, render, main, …)   [egui/wgpu architecture]
│   ├── visuals/             (bars.wgsl, fire.wgsl, wave.wgsl — old shader set)
│   └── integration/omaviz.service
├── bridge/                  ← SOURCE NOT IN GIT. Only the deployed binary exists
│   └── README.md            (documents the socket contract + JSON frame format; no src)
├── plugin/                  ← current QML/JS (moved from repo root)
│   ├── manifest.json, BarWidget.qml, Panel.qml, Desktop.qml, Model.js, VisualCanvas.qml
│   ├── visuals/             (equalizer.toml, wave.toml, fire.toml)
│   └── tests/model.test.cjs
├── APPLICATION_SPEC.md      (this file)
└── omaviz-v2-spec.md        (historical design proposal)
```

**Caveats:**
- The recovered `daemon/` source (v0.2.0) is the **egui/wgpu/render**
  architecture. The binary currently deployed as `omaviz daemon` exposes only a
  socket + DSP (no rendering window), which suggests it was built from a *later,
  unpublished* revision. `daemon/` is the best available source but may not match
  the running binary exactly.
- `bridge/` **source cannot be recovered** — `git log --all` shows no
  `spectrum-bridge` source file anywhere; it was built outside this repo and
  never committed. The deployed `/home/kishan/.local/bin/omaviz-spectrum-bridge`
  is the only artifact. `bridge/README.md` documents its observed contract so the
  gap is explicit rather than silently missing.
- There is **no `v1` tag**; the available tags are `v0.2.0, v2, v3, v4, v5,
  verified-baseline`. The daemon source lives at `v0.2.0` (and earlier Rust-era
  commits `2cd562c`…`a933c27`).
