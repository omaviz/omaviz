# Omaviz v2 Specification

> **Implementation target:** Full QML (Option A) → migration path to QML + Shaders (Option C)
>
> **Plugin id:** `org.omaviz.visualizer`
>
> **As of:** 2026-08-15 · Omarchy quattro branch

---

## 1. Overview

Omaviz v2 is a ground-up rewrite of the Omarchy audio visualizer as a **native Omarchy plugin**. It replaces the v1 standalone Rust binary (waybar custom module + separate egui settings window) with a `bar-widget` + `panel` pair that runs inside `omarchy-shell`.

### v1 → v2 mapping

| v1 | v2 |
|---|---|
| `omaviz daemon` (Rust, systemd, PipeWire, Unix socket) | **Unchanged.** The daemon keeps capturing audio and broadcasting spectrum frames. |
| `omaviz mini --width N` (waybar custom module, Rust, JSON lines) | **Replaced.** `BarWidget.qml` renders the visualization as stacked rectangles. |
| `omaviz desktop` / `omaviz full` (winit + wgpu window) | **Replaced.** A `panel` shows a preview; a "Detach" button launches the desktop window (a separate Quickshell window). |
| `omaviz settings` (separate egui window) | **Replaced.** The `panel` IS the settings UI — summoned on left-click. |
| Right-click menu (walker) | **Removed.** Right-click does nothing. |
| `omaviz toggle` / `omaviz mode` / `omaviz quit` | **Replaced.** Mode state lives in `shell.json`. |
| `~/.config/omaviz/config.toml` | **Kept.** Daemon + desktop read/write TOML. QML plugin reads via `Model.js`. |

---

## 2. Architecture

```
┌───────────────────────────── omarchy-shell ─────────────────────────────┐
│                                                                          │
│  ┌─ bar-widget (BarWidget.qml) ─────────────────────────────────────┐   │
│  │                                                                   │   │
│  │  Stacked Rectangle visualization (mini mode)                      │   │
│  │  Reads spectrum frames from daemon via Model.js                   │   │
│  │  Left-click → open() → summons panel                              │   │
│  │  Desktop active → render dimmed (icon only)                       │   │
│  │                                                                   │   │
│  └───────────────────────────────────────────────────────────────────┘   │
│                              │                                           │
│                              │ open() / close()                          │
│                              ▼                                           │
│  ┌─ panel (Panel.qml) ───────────────────────────────────────────────┐   │
│  │                                                                   │   │
│  │  ┌─ top 30% ──────────────────────────────────────────────────┐  │   │
│  │  │  Live visualization preview (same Rectangle approach,       │  │   │
│  │  │  slightly larger)                                           │  │   │
│  │  └────────────────────────────────────────────────────────────┘  │   │
│  │                                                                   │   │
│  │  ┌─ visualization dropdown (ComboBox) ─────────────────────────┐  │   │
│  │  │  Bars · Fire · Wave · Spectrum · ...                         │  │   │
│  │  └────────────────────────────────────────────────────────────┘  │   │
│  │                                                                   │   │
│  │  ┌─ per-visualization knobs ───────────────────────────────────┐  │   │
│  │  │  (dynamic, declared in .toml manifests, same as v1)         │  │   │
│  │  │  Slider: Borderless · Liquid edge · Brightness · Peak fall  │  │   │
│  │  └────────────────────────────────────────────────────────────┘  │   │
│  │                                                                   │   │
│  │  ┌─ audio ─────────────────────────────────────────────────────┐  │   │
│  │  │  Slider: Sensitivity · Smoothing                            │  │   │
│  │  └────────────────────────────────────────────────────────────┘  │   │
│  │                                                                   │   │
│  │  ┌─ footer ────────────────────────────────────────────────────┐  │   │
│  │  │  [↺ Reset visualization]              [Detach ↗]            │  │   │
│  │  └────────────────────────────────────────────────────────────┘  │   │
│  │                                                                   │   │
│  └───────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘

┌─ daemon (Rust, unchanged) ───────────────────────────────────────────────┐
│  PipeWire capture → FFT → spectrum frames → Unix socket broadcast       │
│  ~/.config/omaviz/config.toml (read + write)                            │
└──────────────────────────────────────────────────────────────────────────┘
        │
        │ Unix socket (OMAV binary frames)
        │
┌───────▼──────────────────────────────────────────────────────────────────┐
│  Model.js — reads frames from socket, exposes as Qt property model      │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## 3. File Structure

```
~/.config/omarchy/plugins/org.omaviz.visualizer/
├── manifest.json                # Plugin contract
├── BarWidget.qml                # bar-widget entry point (mini mode)
├── Panel.qml                    # panel entry point (settings)
├── Model.js                     # Business logic: socket client, config IO, frame model
├── Config.js                    # Read/write config.toml (shared with daemon)
├── Desktop.qml                  # Detached desktop window (launched via Quickshell)
├── SpectrumClient.qml           # Unix socket client wrapping Model.js frame feed
└── visuals/
    ├── Bars.qml                 # Rectangle-based bars visualization
    ├── BarsManifest.qml         # Knob declarations (mirrors v1 .toml)
    ├── Fire.qml                 # Rectangle-based fire visualization
    ├── FireManifest.qml
    ├── Wave.qml
    ├── WaveManifest.qml
    └── (more winamp-style visuals)
```

---

## 4. Plugin Contract (`manifest.json`)

```json
{
  "schemaVersion": 1,
  "id": "org.omaviz.visualizer",
  "name": "Omaviz",
  "version": "2.0.0",
  "author": "kishan",
  "description": "Audio visualizer — winamp-style spectrum, mini bar + desktop detach",
  "kinds": ["bar-widget"],
  "entryPoints": {
    "barWidget": "BarWidget.qml"
  },
  "barWidget": {
    "displayName": "Omaviz",
    "description": "Audio visualizer with winamp-style spectrum",
    "category": "Audio",
    "allowMultiple": false,
    "defaultSection": "right"
  }
}
```

**Key points:**
- Single `bar-widget` kind. The panel is loaded internally via `Loader`, not declared as a separate kind (follows the clock plugin pattern).
- `allowMultiple: false` — only one visualizer instance.
- `defaultSection: "right"` — appears in the bar's right section by default (user can move with `omarchy bar move`).

---

## 5. Bar Widget (`BarWidget.qml`)

Extends the `BarWidget` base type from `qs.Commons` (same as `omarchy.clock`).

### Responsibilities

1. **Render visualization** as stacked `Rectangle`s in the bar slot.
2. **Read spectrum frames** from `Model.js` (which maintains a Unix socket client to the daemon).
3. **Handle left-click** → `open()` the panel.
4. **Handle right-click** → nothing (no menu).
5. **Handle desktop-active state** → render dimmed/icon-only.
6. **Handle silent state** → render idle state.

### Sizing

- `implicitWidth`: dynamic, based on configured band count × band width.
- `implicitHeight`: bar height (driven by `Style.bar.iconSlot`).
- Band width and gap are configurable via `setting("bandWidth", 3)` and `setting("bandGap", 1)`.

### Visualization rendering

```
For each band i in 0..n_bands:
    value = frame.bands[i] * sensitivity * gain
    value = clamp(value, floor, 1.0)
    Rectangle {
        x: i * (bandWidth + bandGap)
        width: bandWidth
        height: value * parent.height
        y: parent.height - height
        color: mix(lowColor, highColor, i / n_bands)
    }
```

### Click behavior

```qml
onPressed: function(button) {
    if (button === Qt.LeftButton) root.open()
    // Right-click: intentionally does nothing (no menu)
    // Middle-click: intentionally does nothing
}
```

### Mode states (from v1 concept, simplified)

| State | Condition | Bar renders |
|---|---|---|
| Mini active | `!desktopActive && !paused` | Live visualization |
| Desktop active | `desktopActive` | Dimmed (icon only) |
| Paused | `paused` | Dimmed |
| Silent | No audio | Idle (flat bars) |

---

## 6. Panel (`Panel.qml`)

A `QsWindow` or floating panel, loaded via `Loader` in `BarWidget.qml` with `active: true` and `visible: false`, shown via `open()`.

### Layout

```
┌────────────────────────────────────────────────────┐
│  ┌─ viz-canvas (30%) ──────────────────────────┐  │
│  │  Same Rectangle visualization as bar,        │  │
│  │  slightly larger for preview                 │  │
│  └──────────────────────────────────────────────┘  │
│                                                    │
│  ┌─ dropdown ──────────────────────────────────┐  │
│  │  [🔥 Fire ▾]                                │  │
│  └──────────────────────────────────────────────┘  │
│                                                    │
│  Visualization Options                            │
│  ┌──────────────────────────────────────────────┐  │
│  │ Borderless  ━━━━━━━━━━━●━━━━━━━━━━           │  │
│  │ Liquid edge ━━━━━━━━●━━━━━━━━━━━━           │  │
│  │ Brightness  ━━━━━━━━━●━━━━━━━━━━━           │  │
│  │ Peak fall   ━━━━━●━━━━━━━━━━━━━━━           │  │
│  └──────────────────────────────────────────────┘  │
│                                                    │
│  Audio                                            │
│  ┌──────────────────────────────────────────────┐  │
│  │ Sensitivity ━━━━━━━━━━●━━━━━━━━━━           │  │
│  │ Smoothing   ━━━━━━━━●━━━━━━━━━━━━           │  │
│  └──────────────────────────────────────────────┘  │
│                                                    │
│  ┌──────────────────────────────────────────────┐  │
│  │ ↺ Reset visualization        [Detach ↗]      │  │
│  └──────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────┘
```

### Dropdown

- `ComboBox` or custom `Menu` listing available visualizations.
- Populated from `Model.visualizations` — a list of `{ name, label }` objects read from `visuals/` directory or a registry.
- On selection change: `Model.selectVisualization(name)` → updates `shell.json` → knobs re-bind to new visualization's declared parameters.
- Knobs come from the visualization's manifest (e.g., `FireManifest.qml` declares `borderless`, `smoothing`, `brightness`, `peak_fall`).

### Per-visualization knobs

- Each visualization has a companion `Manifest.qml` that declares its parameters (name, label, min, max, default, boolean).
- The panel renders one `Slider` per declared parameter (or `Switch` for booleans).
- Values bind to `setting("viz_fire_borderless", 1.0)` etc.
- Auto-save: every slider change writes through to `shell.json` immediately via `root.bar.shell.updateEntryInline()`.

### Audio section

- Two sliders: `Sensitivity` and `Smoothing`.
- Values bind to `setting("sensitivity", 1.0)` and `setting("smoothing", 0.5)`.

### Footer

- **↺ Reset visualization**: Resets current visualization's knobs to their manifest defaults.
- **Detach ↗**: Closes the panel and launches the desktop window (see §9).

### Panel lifecycle (Omarchy contract)

```qml
// In BarWidget.qml
readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
function open() { if (panelLoader.item) panelLoader.item.open() }
function close() { if (panelLoader.item) panelLoader.item.close() }

Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
        root.injectPanel()
        Qt.callLater(root.injectPanel)
    }
}

function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
}
```

---

## 7. Config & State Management

### Config file: `~/.config/omaviz/config.toml` (kept from v1)

```toml
[audio]
sensitivity = 1.0
smoothing = 0.5
bands = 32

[visual]
active = "fire"          # Current visualization name

# Per-visualization knob values
[visual.fire]
borderless = 1.0
smoothing = 0.5
brightness = 1.0
peak_fall = 0.08

[visual.bars]
# ... bars-specific knobs

[desktop]
# Desktop window settings (position, size, etc.)
x = 100
y = 100
width = 640
height = 200
```

### State in `shell.json` (Omarchy)

```json
{
  "bar": {
    "layout": {
      "right": [
        { "id": "org.omaviz.visualizer", "visual": "fire", "sensitivity": 1.0, "smoothing": 0.5 }
      ]
    }
  }
}
```

The plugin's per-instance settings are inline on the `shell.json` entry. Global config (visualization knobs, desktop position) lives in `config.toml`.

### `Config.js` responsibilities

- Read `config.toml` on startup.
- Watch `config.toml` for changes (the daemon writes to it; the plugin hot-reloads).
- Write `config.toml` when the user changes a setting in the panel.
- Expose config as QML properties: `Config.activeVisual`, `Config.sensitivity`, `Config.smoothing`, `Config.visualKnobs`.

### `Model.js` responsibilities

- Maintain the Unix socket client connection to the daemon (`/run/user/1000/omaviz.sock`).
- Parse OMAV binary frames (same wire format as v1).
- Expose latest frame as a Qt property: `Model.frame` → `{ bands: [], energy, beat, silent }`.
- Expose `Model.visualizations` — list of available visualization names.
- Expose `Model.visualizationManifest(name)` — parameter declarations for a visualization.
- Handle reconnection on daemon restart.

---

## 8. SpectrumClient (Unix socket in QML)

QML/JS cannot directly open a Unix socket and parse binary frames. Two approaches:

### Approach A: `Quickshell.Io.Process` (preferred)

Use a small helper process (could be the existing `omaviz` binary or a new minimal Rust/C client) that reads the socket and emits JSON lines on stdout:

```qml
Process {
    id: spectrumSource
    command: ["omaviz-spectrum-bridge"]  // small binary: reads OMAV frames, prints JSON per line
    running: true
    stdout: SplitParser {
        onRead: (line) => {
            var frame = JSON.parse(line)
            Model.updateFromFrame(frame)
        }
    }
}
```

The bridge binary does the binary parsing and emits:
```json
{"bands":[0.1,0.5,0.9,...],"energy":0.37,"beat":0.88,"silent":false}
```

### Approach B: Pure JS over `WebSocket` or `XMLHttpRequest`

Not viable — no Unix socket support in QML JS.

**Decision: Approach A.** The bridge is a thin wrapper (~50 lines Rust) that the daemon already has the data for. It reuses the existing `omaviz ipc` connect/broadcast path.

---

## 9. Desktop Window (Detach)

### Behavior

- Clicking **Detach ↗** in the panel:
  1. Closes the panel.
  2. Sets `desktopActive = true` in plugin state.
  3. Launches `Desktop.qml` as a standalone Quickshell window (`quickshell -p ~/.config/omarchy/plugins/org.omaviz.visualizer/Desktop.qml`).
  4. The bar widget renders dimmed.
- Closing the desktop window:
  1. Sets `desktopActive = false`.
  2. Bar widget resumes live visualization.
  3. Panel remains closed (user re-opens with left-click).

### `Desktop.qml`

- A full Quickshell window (not a panel) with the visualization at full size.
- Same rendering approach (stacked Rectangles) but larger.
- Reads frames from the same `Model.js` / socket bridge.
- On close: writes `desktopActive = false` back to the plugin via IPC or config file.

### Alternative: shader-based desktop

The detached desktop could optionally use the existing wgpu shaders (from v1) if we keep a `omaviz desktop` Rust binary around. This would give GPU-accelerated visuals in the detached window while the mini + panel use QML rectangles. This is compatible with the v2 architecture and can be toggled via a `setting("desktopUsesShader", false)`.

---

## 10. Winamp Visualizations

The "bring back winamp visualizations" requirement is addressed by providing multiple QML visualizations that mimic classic winamp styles:

| Name | Visual style | Knobs |
|---|---|---|
| `bars` | Classic spectrum bars with rounded caps, beat glow | gap, glow, beat_boost |
| `fire` | Fluid, borderless spectrum with peak-hold bricks | borderless, smoothing, brightness, peak_fall |
| `wave` | Mirrored spectrum ribbon with bloom | amplitude, bloom, mirror |
| `spectrum` | Scrolling spectrogram (waterfall) | scroll_speed, color_map, decay |
| `particles` | Beat-reactive particle field | density, particle_life, gravity |
| `starfield` | Starfield warp driven by energy | warp_speed, star_count, trail |

Each visualization is a self-contained `*.qml` file plus a `Manifest.qml` declaring its knobs. Adding a new one drops two files into `visuals/` — no code changes elsewhere.

### Manifest format (QML singleton)

```qml
// visuals/FireManifest.qml
pragma Singleton
import QtQuick

QtObject {
    property string name: "fire"
    property string label: "Fire"
    property var params: [
        { name: "borderless", label: "Borderless (merged flame)", type: "bool", default: true },
        { name: "smoothing", label: "Liquid edge", type: "real", min: 0, max: 1, default: 0.5 },
        { name: "brightness", label: "Flame brightness", type: "real", min: 0.2, max: 2.0, default: 1.0 },
        { name: "peak_fall", label: "Peak-hold fall speed", type: "real", min: 0.01, max: 0.5, default: 0.08 }
    ]
}
```

The panel queries `Model.visualizationParams(name)` to render the correct knobs for the selected visualization.

---

## 11. Mode State Machine (v2 simplification)

v2 has exactly **two live display modes**, mutually exclusive:

| Mode | Bar widget | Panel | Desktop window |
|---|---|---|---|
| **Mini** (default) | Live visualization | Summoned on click | Closed |
| **Desktop** | Dimmed/icon | Closed | Open |

There is no "Off" state in the v2 plugin model — the daemon keeps running (it's a system service), and the bar widget is always visible. If the user wants silence, they pause audio at the source.

**State transitions:**
- Mini → Desktop: click **Detach ↗** in panel.
- Desktop → Mini: close desktop window (window `onClosed` signal sets state back).

This satisfies: *"mini mode vs desktop (either of them active at a time)"*.

---

## 12. Auto-save

Every user interaction writes through immediately:

| Action | Persisted to |
|---|---|
| Change visualization dropdown | `shell.json` via `updateEntryInline()` + `config.toml` via `Config.js` |
| Move a knob slider | `shell.json` + `config.toml` |
| Move sensitivity/smoothing | `shell.json` + `config.toml` |
| Click "Reset" | `shell.json` + `config.toml` (reset to defaults) |
| Detach to desktop | `shell.json` (sets `desktopActive: true`) |
| Close desktop | `shell.json` (sets `desktopActive: false`) |

No "Save" / "Cancel" buttons. Change is the save.

---

## 13. No Right-click Menu

v1 had a right-click menu (via walker `--dmenu`) with items like "Toggle desktop", "Settings", "Sensitivity +", "Sensitivity -", "Select visualization", "Quit".

v2 removes this entirely:
- Right-click on the bar widget: **does nothing**.
- All settings are in the panel (left-click).
- Sensitivity is adjusted via the slider in the panel (no scroll-wheel binding).

---

## 14. Migration Path: Option A → Option C (QML + Shaders)

The v2 architecture is designed so that the rendering backend can be swapped without changing the plugin contract, `BarWidget.qml`, `Panel.qml`, or `Model.js`.

### What changes

| Component | Option A (Rectangles) | Option C (Shaders) |
|---|---|---|
| `visuals/Bars.qml` | `Repeater { Rectangle {} }` | `ShaderEffect { fragmentShader: ... }` |
| `visuals/Fire.qml` | `Repeater { Rectangle {} }` with peak bricks | `ShaderEffect { fragmentShader: ... }` |
| `SpectrumClient` | JSON lines from bridge | Same (shader reads band data) |
| Panel preview | Rectangles (same as bar) | `ShaderEffect` (same shader as bar) |
| Desktop window | QML Rectangles | `ShaderEffect` (GLSL) |

### What stays the same

- `manifest.json`
- `BarWidget.qml` (instantiates whichever visualization is selected)
- `Panel.qml` (dropdown + knobs — visualization-agnostic)
- `Model.js` (frame source — provides band data regardless of renderer)
- `Config.js` (config format)
- `Desktop.qml` (host — just embeds the visualization QML)
- Per-visualization knob manifests
- Daemon (Rust, unchanged)

### The porting step

When migrating to Option C:

1. Replace the body of `visuals/Bars.qml` with a `ShaderEffect` using a GLSL fragment shader.
2. Replace the body of `visuals/Fire.qml` similarly.
3. The GLSL shaders are ports of the existing WGSL shaders (`visuals/fire.wgsl`, etc.) — same math, different uniform binding syntax.
4. The shader reads band data via a `Texture` or `uniform array<float>` updated each frame from `Model.js`.

### Timing

Option C is **not** in v2 MVP. Ship v2 with rectangles first, then port shaders visualization-by-visualization as time allows. The architecture supports both simultaneously — a visualization can declare `"renderer": "rectangles"` or `"renderer": "shader"` in its manifest.

---

## 15. Implementation Plan

### Epic 1: Plugin skeleton

| Story | Task | Est. | Progress |
|---|---|---|---|
| **S1.1 Create plugin directory and manifest** | Create `~/.config/omarchy/plugins/org.omaviz.visualizer/manifest.json` with bar-widget contract. Run `omarchy-shell shell rescanPlugins`. Verify discovery. | S | 0% |
| **S1.2 Stub BarWidget.qml** | Extend `BarWidget`, render a static row of colored rectangles. Left-click logs to console. | S | 0% |
| **S1.3 Stub Panel.qml** | Create a `QsWindow` with a visualization canvas (30%), dropdown placeholder, and footer. Wire `open()` / `close()`. | S | 0% |
| **S1.4 Wire panel into bar widget** | `Loader` in `BarWidget.qml`, `injectPanel()`, verify panel summons on click and closes on second click. | S | 0% |

### Epic 2: Frame pipeline

| Story | Task | Est. | Progress |
|---|---|---|---|
| **S2.1 Write `omaviz-spectrum-bridge`** | Minimal Rust binary: connect to `omaviz.sock`, parse OMAV frames, emit JSON lines on stdout. | M | 0% |
| **S2.2 `SpectrumClient.qml`** | Wrap bridge as `Quickshell.Io.Process`, parse JSON, update `Model.frame`. | S | 0% |
| **S2.3 `Model.js` frame model** | Expose `frame` property, handle reconnection, expose `visualizations` list. | S | 0% |
| **S2.4 `Config.js` reader** | Read `config.toml`, expose properties, watch for changes. | S | 0% |

### Epic 3: Visualizations

| Story | Task | Est. | Progress |
|---|---|---|---|
| **S3.1 Bars visualization** | `Bars.qml` — spectrum bars with rounded caps and beat glow. | S | 0% |
| **S3.2 Fire visualization** | `Fire.qml` — fluid spectrum with peak-hold bricks. | M | 0% |
| **S3.3 Wave visualization** | `Wave.qml` — mirrored spectrum ribbon. | S | 0% |
| **S3.4 Spectrum visualization** | `Spectrum.qml` — scrolling spectrogram. | M | 0% |
| **S3.5 Visualization registry** | `Model.js` auto-discovers `visuals/*.qml` and populates dropdown. | S | 0% |

### Epic 4: Settings panel

| Story | Task | Est. | Progress |
|---|---|---|---|
| **S4.1 Dynamic knob rendering** | Panel reads `Model.visualizationManifest(name)` and renders `Slider` / `Switch` per declared param. | M | 0% |
| **S4.2 Audio settings** | Sensitivity + Smoothing sliders bound to `Config.js`. | S | 0% |
| **S4.3 Auto-save** | Every slider change calls `updateEntryInline()` + `Config.write()`. | S | 0% |
| **S4.4 Reset button** | Resets current visualization's knobs to manifest defaults. | S | 0% |
| **S4.5 Dropdown selection** | ComboBox bound to `Model.visualizations`, updates `Config.activeVisual`. | S | 0% |

### Epic 5: Desktop detach

| Story | Task | Est. | Progress |
|---|---|---|---|
| **S5.1 `Desktop.qml`** | Quickshell standalone window embedding selected visualization. | M | 0% |
| **S5.2 Detach button** | Closes panel, launches desktop, sets `desktopActive = true`. | S | 0% |
| **S5.3 Desktop close → mini resume** | Window `onClosed` sets `desktopActive = false`, bar resumes. | S | 0% |
| **S5.4 Desktop position persistence** | Write window position to `config.toml` on move, read on launch. | S | 0% |

### Epic 6: Polish & migration prep

| Story | Task | Est. | Progress |
|---|---|---|---|
| **S6.1 Silent/idle states** | Handle `frame.silent` → flat/dimmed bars. | S | 0% |
| **S6.2 Desktop-active dimmed state** | Bar renders icon-only when desktop is open. | S | 0% |
| **S6.3 Install script** | `install.sh` copies plugin to `~/.config/omarchy/plugins/`, enables it, adds to `shell.json`. | S | 0% |
| **S6.4 Shader-ready architecture** | Add `"renderer"` field to visualization manifests; `visuals/*.qml` exposes a `Visualization` interface (frame in, paint out). | M | 0% |
| **S6.5 WGSL → GLSL port (Option C)** | Port `fire.wgsl` to `Fire.qml` `ShaderEffect`. One visualization at a time. | L | 0% |

---

## 16. Risks & Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Frame bridge adds latency | Visualizer lags audio | Bridge is minimal (parse + print JSON). Test with `time` on a frame round-trip. Target <5ms. |
| Quickshell `Process` cleanup | Zombie bridge process on shell restart | Bridge exits on SIGPIPE when parent dies. Use `Quickshell.Io.Process` which handles lifecycle. |
| QML Rectangle perf with 64+ bars | Frame drops in bar | Limit bar mode to ≤48 bars (configurable). Panel preview can show more. |
| `config.toml` race: daemon writes, plugin reads | Torn read / parse error | Daemon already uses write-then-rename (atomic). Plugin reloads on `QFileSystemWatcher` notification. |
| Panel position / anchoring | Panel appears off-screen or misaligned | Use `anchorItem: button` (same as clock panel) to position relative to the bar widget. |
| Multiple visualizations with conflicting knob names | Settings collision | Namespace knobs as `viz_<name>_<param>` in `config.toml`. |

---

## 17. Open Questions

1. **Should the daemon remain a systemd service, or become an Omarchy `service` plugin?**
   - v2 keeps it as systemd (unchanged). Future: fold into `omarchy-shell` as a `service` plugin for PipeWire capture + FFT. This removes the Unix socket entirely (shared memory instead).

2. **Should `omaviz-spectrum-bridge` be a separate binary or part of the main `omaviz` binary?**
   - Separate binary is cleaner (single responsibility). Could be a subcommand: `omaviz bridge-spectrum`.

3. **What happens to `omaviz desktop` (Rust wgpu binary) in v2?**
   - v2 deprecates it in favor of `Desktop.qml`. But the shader-based desktop binary can coexist as an optional accelerator (see §9).

4. **Should the panel use `QsWindow` or `Popup`?**
   - Need to test which anchors correctly to a bar widget slot. Clock uses a `Loader`-loaded panel; follow that pattern.

---

## 18. Future Improvements (post-v2)

- **Option C shaders**: GPU-accelerated visuals in bar + panel.
- **Service-plugin daemon**: Move PipeWire capture into `omarchy-shell` as a `service` plugin. Eliminates Unix socket and bridge binary.
- **Mpris integration**: Show currently-playing track info in panel (like `omarchy.media`).
- **Hyprland window rules**: Float the desktop window, set rounded corners, blur background.
- **Custom shader import**: User drops a `.glsl` file into `~/.config/omaviz/visuals/` and it appears in the dropdown (same "drop in a shader" promise as v1, but for GLSL).
- **Fullscreen mode**: `F11` or double-click on desktop window → borderless fullscreen.

---

*End of specification.*
