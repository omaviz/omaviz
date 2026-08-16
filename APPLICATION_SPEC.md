# omaviz — Application Specification (current implementation)

> **Plugin id:** `org.omaviz.visualizer`
> **Version:** 2.0.0 (manifest) · code line `v3`+ as of 2026-08-16
> **Status:** Self-contained Omarchy QML plugin. No Rust daemon, no WGSL, no egui
> in the plugin itself. A small external `omaviz-spectrum-bridge` binary provides
> the audio→spectrum frames; everything else is QML + JS rendered on a Canvas.

This document describes what is **actually implemented and shipped** (verified by
code + runtime tests), superseding the earlier Rust/WGSL design notes in
`omaviz-v2-spec.md` (that file is the original design proposal; this one is the
source of truth). The GPU/WGSL migration path is kept as a forward-looking section.

---

## 1. Goals & Non-Goals

**Goals**
- React to system playback audio (not the microphone).
- Live in the Omarchy bar as a mini stacked-rectangle visualizer.
- Optional detached **desktop window** (floating, ~600×200) for a larger view.
- A settings panel (summoned on click) to switch visualization + style, tweak
  knobs, and toggle color sync — no rebuild needed.
- Stay out of the user's way; the mini is always present, the desktop only on demand.

**Non-Goals (current)**
- No GPU/WGSL rendering yet — visuals are Canvas-2D in `VisualCanvas.qml`.
- No microphone monitoring (bridge captures the sink monitor only).
- No separate egui/GTK settings window — the panel is QML.

---

## 2. Architecture

```
┌────────────────────── omarchy-shell (one Quickshell process) ─────────────────────┐
│                                                                                   │
│  BarWidget.qml  (bar-widget, always present)                                      │
│   ├─ stacked Rectangle bars (mini mode)                                           │
│   ├─ reads frames from Model.spectrumData                                        │
│   ├─ left-click → open() the panel; desktop.active=true → render dimmed/paused   │
│   └─ Loader → Panel.qml (settings UI, loaded in-process)                         │
│                                                                                   │
│  Panel.qml  (settings)                                                            │
│   ├─ live preview (VisualCanvas.qml, Bars/Wave + Classic/Fire style)              │
│   ├─ VISUALIZATION dropdown (Bars · Wave)                                        │
│   ├─ STYLE dropdown (Classic · Fire)   ← Fire is a STYLE of Bars, not a viz      │
│   ├─ OPTIONS knobs (dynamic, from visuals/*.toml)                                 │
│   ├─ AUDIO (sensitivity / smoothing), color-sync toggle                          │
│   └─ footer: Reset · Detach (launches Desktop.qml via Quickshell)                │
│                                                                                   │
│  Model.js  (shared business logic, .pragma library)                              │
│   ├─ spectrumData  — latest frame (bands/energy/beat/silent)                     │
│   ├─ config IO      — readConfigFromText / writeConfigKey (~/.config/omaviz/      │
│   │                  config.toml)                                                 │
│   └─ visual discovery — discoverVisualsFromText / visualParamsFromText /         │
│                      visualConfigValues                                          │
│                                                                                   │
│  VisualCanvas.qml  (self-contained Canvas-2D renderer, no shell-only imports)    │
│   └─ draws Bars / Wave / Fire-style from `bands`                                 │
└───────────────────────────────────────────────────────────────────────────────────┘
        │  frames (JSON lines on stdout)
        ▼
┌── omaviz-spectrum-bridge (external binary, ~/.local/bin) ────────────────────────┐
│  PipeWire sink-monitor capture → FFT → JSON spectrum frames → stdout             │
│  (the only "daemon"; minimal, one instance per consumer that launches it)        │
└───────────────────────────────────────────────────────────────────────────────────┘
```

- **Single shell process.** The bar widget, the panel (loaded via `Loader`), and
  the desktop window's *config* all live in `omarchy-shell`. The desktop window is
  a *separate* Quickshell process launched on Detach.
- **Frames** are produced by `omaviz-spectrum-bridge` (a standalone binary) and
  consumed by a `Process` in `BarWidget.qml`/`Model.js` via a `SplitParser`; each
  JSON line updates `Model.spectrumData`. The bar reads `spectrumData.bands`.
- **Config** is the shared `~/.config/omaviz/config.toml` (also read by the bridge
  for `audio.*`). The panel reads/writes it through `Model.js`; the bar keeps its
  own watching `FileView` so detach-close → resume propagates cross-process.

---

## 3. Files

```
~/.config/omarchy/plugins/org.omaviz.visualizer/
├── manifest.json          # Plugin contract (bar-widget kind)
├── BarWidget.qml          # bar-widget entry (mini); loads Panel via Loader
├── Panel.qml              # settings panel (preview, dropdowns, knobs, detach)
├── Desktop.qml            # detached 600×200 window (Quickshell, launched on Detach)
├── Model.js               # logic: frames, config IO, visual discovery (.pragma library)
├── VisualCanvas.qml       # self-contained Canvas-2D renderer (Bars/Wave/Fire-style)
└── visuals/
    ├── equalizer.toml      # label "Bars"  — bar params (bar_count, colour_scheme, peak_fall)
    ├── wave.toml           # label "Wave"  — wave params
    ├── fire.toml           # label "Fire"  — fire-style params (intensity, borderless, …)
    └── *.wgsl              # placeholders for the future GPU migration (see §10)
```

`tests/model.test.cjs` — 35 node tests for `Model.js` (run `node tests/model.test.cjs`).

---

## 4. Visualizations & the Fire-is-a-Style model

- **Visualizations:** `Bars` (equalizer.toml) and `Wave` (wave.toml). These are the
  entries in the VISUALIZATION dropdown.
- **Styles:** `Classic` and `Fire`. **Fire is a STYLE of the Bars visual, not a
  separate visualization** — it is selected in the STYLE dropdown, not the
  VISUALIZATION dropdown. When style=Fire and visual=Bars, the panel shows the
  Bars knobs **plus** the Fire knobs (both written to their own
  `[visual.<source>]` sections). `VisualCanvas.qml` renders the winamp-style flame
  (red→yellow gradient, peak-cap bricks, energy glow) when `style==="fire"`.
- Visuals/params are **data-driven**: `visuals/<name>.toml` declares `params`
  (label, type, min/max/default, section). Adding a knob needs no rebuild — the
  panel enumerates them at runtime via `Model.discoverVisualsFromText` +
  `visualParamsFromText`. `parseVisualToml` keeps visual-level `label` separate
  from per-param `label` (a bug fixed earlier: the top-level label handler used to
  swallow param labels).

---

## 5. Configuration (`~/.config/omaviz/config.toml`)

Key sections (read by `Model.readConfigFromText`):
- `[audio]` — `sensitivity`, `smoothing`, `bands` (shared defaults).
- `[mini]` / `[desktop]` / `[full]` — `visual`, `style`, `color_sync`, `active`,
  `fps`, `sensitivity`, `smoothing`, `bands`.
  - `style` (mini) vs `styleDesktop` (desktop) so the detached window can keep its
    own style; `selectStyle` writes both.
  - `desktop.active = "true"` → the mini pauses (dimmed). Set on Detach, cleared on
    window close (cross-process via the bar's watching FileView, and as an
    in-process safety net in `detachProc.onExited`).
- `[visual.<name>]` — per-param overrides, e.g. `[visual.equalizer] bar_count=48`,
  `[visual.fire] intensity=1.5`. Written by `setKnob` to the param's own source
  section (so Bars' and Fire's `peak_fall` don't collide).
- `[palette]` — present (bridge/legacy), not used by the QML renderer.

**Write model (important):** the panel keeps an authoritative in-memory
`configText` buffer. `writeConfigKey` mutates it synchronously; `configWrite`
(`FileView`, `watchChanges:false`) only persists to disk. This avoids the earlier
bug where `FileView.setText()` did not update `text()` synchronously and a
self-watch reverted the value — which made every control need a second click.

`writeConfigKey` inserts keys **within** their section (no duplicate-key
corruption), and never creates a second `[mini]`/`[desktop]` header.

---

## 6. Settings Panel behavior

- **Preview** (top): live `VisualCanvas` bound to the active visual + style + the
  live spectrum (`bands`, `silent`, `colorSync`, `barCount`, `colourScheme`).
- **VISUALIZATION dropdown:** Bars · Wave (Fire excluded — it is a style).
- **STYLE dropdown:** Classic · Fire.
- **OPTIONS:** dynamic knobs from the active visual's `.toml` (+ Fire knobs when
  style=Fire). Each knob writes to `[visual.<source>]`. Values reflect on the first
  change (no second click).
- **AUDIO:** sensitivity / smoothing sliders.
- **Color sync (mini):** toggle → writes `mini.color_sync`; the mini bar recolors
  (multicolor gradient) instead of monochrome. Pushed to the bar immediately via
  `hostWidget.applyConfig(next)` so it does not depend on disk-watch timing.
- **Reset:** restores the active visual's params to defaults.
- **Detach:** launches `Desktop.qml` (600×200 floating window) and pauses the mini.

---

## 7. Detach / desktop window lifecycle

- **Detach** (`detach()`): writes `desktop.active=true` (mini pauses), then launches
  `Desktop.qml` via `detachProc` (a Quickshell `Process`).
- **Re-launch fix:** `detachProc` has a `StdioCollector` draining stdout so its
  `running` flag flips to `false` when the child window closes. A second Detach
  forces `running=false → true` (`Qt.callLater`) so Quickshell always re-spawns the
  window. Without the collector, `running` stayed `true` after the first close and
  the second Detach was a no-op (window never reopened, mini left stuck paused).
- **Close → resume:** `Desktop.qml` writes `desktop.active=false` on close; the bar's
  watching `FileView` picks it up → mini resumes. `detachProc.onExited` is a safety
  net that also clears `active` if a launch failed/was killed, so the mini can never
  be left stuck paused.
- **Desktop window** renders the same `VisualCanvas` at larger size; `styleDesktop`
  drives its Fire/Classic choice.

---

## 8. Rendering (`VisualCanvas.qml`)

- Self-contained Canvas-2D (no `qs.Commons`/`qs.Ui` imports) so it loads standalone
  inside `Loader` + `Binding` (the `when: item` guard avoids null-target binds).
- Modes: `Bars` (stacked rectangles), `Wave` (sine-ribbon), `Fire` (winamp flame:
  red→yellow gradient per band, peak-cap bricks, energy-reactive background glow).
- `barCount` downsamples the 64-band spectrum for the requested bar density;
  `colourScheme` selects a color preset; `colorSync` drives the mini multicolor.

---

## 9. Testing

- `tests/model.test.cjs` — 35 node tests (no deps). Covers: TOML read/write
  (`writeConfigKey` no duplicate keys, in-section insert), `readConfigFromText`
  (style/styleDesktop/desktopActive/colorSync), visual discovery + param parsing
  (labels preserved), `visualConfigValues` from config (boolean honored, not
  parseFloat'd), the Fire-is-a-style contract (VIZ excludes Fire), single-write
  reflection (the 2-click regression guard), color-sync + pause round-trips, and
  the stale-`active` recovery path.
- Run: `node tests/model.test.cjs`.
- QML-runtime behaviors (layout/clipping, drag feel, actual pixel output) are **not**
  covered by unit tests — they require a live Quickshell scene. Verified manually
  via runtime logs (`qs log`) + logic tests, not screenshots (the panel is a
  Quickshell layer not captured by window/screen tools).

---

## 10. Migration path → GPU / WGSL (future)

The current renderer is Canvas-2D for portability and zero GPU dependencies. The
forward path to GPU-accelerated, shader-driven visuals (the original v2 "Option C"):

1. **Keep the data contract.** `Model.spectrumData` (bands/energy/beat/silent) and
   the `visuals/<name>.toml` param model are shader-agnostic. Shaders consume the
   same `bands` array + the same `[visual.<name>]` params.
2. **Swap the renderer, not the shell.** Replace `VisualCanvas.qml`'s Canvas-2D draw
   with a `Wgpu`/`Shader` instance that loads `visuals/<name>.wgsl` (+ `_common.wgsl`
   prelude, already present as placeholders). The `BarWidget`/`Panel`/`Desktop`
   wrappers, dropdowns, and config IO stay unchanged.
3. **Shader discovery.** Promote `visuals/*.wgsl` from placeholder to real shaders;
   `discoverVisualsFromText` already enumerates the dir, so shader visuals appear in
   the dropdown with no shell change.
4. **Per-visual fit knobs** (`mini_simplify`, `full_detail`, …) become shader
   uniforms — the same `.toml` `params` feed them.
5. **Detach window** becomes the natural home for full-quality GPU shaders; the mini
   bar keeps a cheap Canvas-2D (or a tiny shader) for performance.
6. **Risk:** GPU process teardown on Wayland (the v1 daemon intentionally leaked its
   `App` on exit to dodge a wgpu+Mesa EGL segfault). Any GPU migration must keep the
   "leak-on-exit / never crash the shell" discipline and must not launch GPU surfaces
   from the agent's verification path.

This keeps the plugin self-contained and incrementally upgradable: today Canvas-2D,
tomorrow drop-in WGSL, same UI and config.

---

## 11. Operational notes

- Edit the **repo** (`~/workspace/omaviz`) first, then copy changed files into the
  live plugin dir to test. Never edit the live copy directly.
- The spectrum bridge is a separate binary; only one consumer launches it (the bar).
  Multiple stray `Desktop.qml` test windows monopolize the PipeWire capture and starve
  the bar — kill them by explicit PID after visual checks.
- `desktop.active` must be `"false"` for the mini to render; a killed detach window
  can leave it stuck `true` (cleared by `detachProc.onExited` or manually).
