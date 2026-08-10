# omaviz — Application Specification

> Audio visualizer for Omarchy (Arch + Hyprland + Waybar). A daemon captures
> system audio and broadcasts spectrum frames over a Unix socket; lightweight
> clients (a Waybar text module, a floating desktop window, a fullscreen
> window, and a settings panel) consume those frames and render them with
> drop-in WGSL shaders.

This document captures the shipped features and the key engineering decisions
made during development, including the root-cause fixes for the three
"nothing works" failure modes reported by the user.

---

## 1. Goals & Non-Goals

**Goals**
- React to whatever the system is *playing* (not the microphone).
- Live in the Waybar as a tiny unicode-bar module, plus optional desktop /
  fullscreen GPU windows.
- Let the user swap visualizations and tweak per-display fit without a rebuild
  (shaders are data, not code).
- Stay out of the user's way: the bar module is always present; the desktop
  window only appears on demand.

**Non-Goals**
- No microphone monitoring (capture is sink-monitor only).
- No web/HTML UI — the settings panel is an `egui` GPU canvas themed to match
  Omarchy; it is **not** CSS-colourable.
- No GTK dependency. The earlier GtkBuilder XML menu was abandoned.

---

## 2. Architecture

```
┌────────────┐   PipeWire    ┌──────────────────┐   Unix socket    ┌─────────────────────┐
│ system sink│ ──monitor──▶  │ omaviz daemon     │ ──frames(JSON)──▶ │ clients (any number) │
│ (playing    │              │  - capture.rs      │   /run/user/1000/  │  - mini   (waybar)   │
│  audio)     │              │  - dsp.rs (FFT)    │   omaviz.sock     │  - desktop (floating) │
└────────────┘              │  - ipc.rs (server) │                  │  - full    (fullscreen)│
                           └──────────────────┘                  │  - settings (egui)    │
                                                                └─────────────────────┘
```

- **Single daemon**, one capture stream, one FFT analyzer, broadcasts to all
  connected clients. Clients never touch audio directly.
- **Clients are pure consumers** of the broadcast frame (`ipc::Frame`): bands
  vector, energy, beat flag, silent flag.
- **One binary, many subcommands.** `omaviz <cmd>` dispatches to daemon, mini,
  desktop, full, settings, menu, etc. The Waybar module runs `omaviz mini`;
  right-click runs `omaviz menu`; left-click runs `omaviz toggle`.

### Process / instance model
- `daemon` acquires a single-instance lock (`instance::WindowKind::Daemon`).
- `desktop` / `full` each acquire their own single-instance lock so a second
  launch focuses the existing window instead of spawning a duplicate.
- The desktop/full renderer intentionally **leaks its `App` on exit** (std::mem::forget)
  to avoid a known wgpu + Mesa + Wayland EGL teardown segfault; GPU resources are
  released by the OS at process exit.

---

## 3. Audio Capture Pipeline (`capture.rs`)

- Backend: **PipeWire** (`pipewire` 0.10 crate), F32LE mono mix-down.
- Captures the **default sink's monitor** (`STREAM_CAPTURE_SINK=true`) so the
  visualizer reacts to playback from any app.
- Sample rate follows the device (rebuilds the analyzer if the sink changes
  clock, e.g. 44.1k ↔ 48k).
- **Decision — do NOT pin `target.object` to `<sink>.monitor` by name.**
  Experiment showed that explicitly setting `target.object` to the monitor node
  name linked to a suspended/idle monitor and produced *silence*, while relying
  on session-manager autoconnect (`STREAM_CAPTURE_SINK`) reliably delivers
  playback audio once the daemon has been running and audio is actually playing.
  (PipeWire creates the monitor node on demand; a short-lived manual daemon may
  not establish the link in time — this is why sterile test tones in a fresh
  daemon read `e=0.000`, but the long-running systemd daemon + real audio works.)

### DSP (`dsp.rs`)
- `realfft` real→complex FFT, `FFT_SIZE = 2048`, Hann window.
- Log-spaced band edges between 30 Hz and ≤16 kHz, count from `audio.bands`.
- Per-band dB→0..1, attack/decay smoothing, global `energy` and a simple
  `beat`/onset estimate. `is_silent()` below `energy < 0.02`.

---

## 4. IPC (`ipc.rs`)

Wire format (little-endian), one frame:
```
magic   u32 = 0x4F4D4156 ("OMAV")
n_bands u16
flags   u16   bit0 = silent
energy  f32
beat    f32
bands   [f32; n_bands]
```
- `Frame::encode` / `Frame::read_from` round-trip (unit-tested).
- `Server` is non-blocking and drops slow/dead clients silently.
- `spawn_reader` lets any client subscribe to the broadcast in its own thread.

---

## 5. Clients

### 5.1 Mini (Waybar module) — `mini.rs`
- Runs as `omaviz mini --width 18`; emits one JSON line per frame:
  ```json
  {"text":"▁▂▃…","tooltip":"omaviz · bars · energy 0.43","class":"active"}
  ```
- `class` states: `active` (audio), `silent` (no audio), `off` (desktop window
  open or paused — dimmed bars), `hidden` (after Quit — module disappears).
- Bars are unicode block glyphs `▁▂▃▄▅▆▇█`; Waybar line-height is 1.0 so a
  single row fills the bar height.
- **Per-display fit** (fixes "too faint"): `mini_gain` amplifies quiet audio
  and `mini_floor` keeps a minimum bar height, so "playing" is clearly different
  from "flat". Both read from `config.mini.extra` with safe defaults.

### 5.2 Desktop (floating window) — `client.rs`
- Launched by left-click (`omaviz toggle`). Floating widget via Hyprland
  windowrule (`class omaviz`, `float`, `size 640 200`, `move 100%-660 60`).
- Double-click toggles fullscreen; `Esc`/`q` closes; `f` toggles fullscreen.
- Hot-reloads config; auto-closes if the bar switches the mode off.

### 5.3 Full (fullscreen) — `client.rs`
- `omaviz full` / `SUPER+SHIFT+V`. Borderless fullscreen, uses the `full` visual.

### 5.4 Settings (egui) — `settings.rs`
- **Split Panel** layout:
  - **Left:** vertical visualization list, current one pre-ticked "active".
  - **Top-right:** live preview rendering from the working config (edits show
    instantly).
  - **Bottom-right:** options for the selected visual, including a **Per-display
    fit** section (bar visuals fill the tiny bar; circular visuals want
    full-screen room).
  - Per-visual **Reset** lives inside the options panel.
  - Footer is **Save / Cancel only**.
- Applies live on Save (writes `config.toml`, daemon/client watchers pick it up).
- Themed to the Omarchy accent (egui selection/accent/hyperlink tints) — no CSS.

---

## 6. Visualizations (`visual.rs` + `visuals/*.wgsl`)

- Discovered at runtime from `visuals/<name>.wgsl` (user config dir first, then
  the source tree). Adding a shader needs **no rebuild**.
- Each visual may declare `<name>.toml` with `params` (per-visual knobs) and
  `extra_params` (mode-only fit knobs stored in the mode's `extra` table, so a
  mini density tweak doesn't leak into the desktop window).
- `visual_kind()` heuristically classifies a visual as **Bars**, **Circular**, or
  **Other** by name (`bar`/`fire`/`wave`/`pulse` → Bars; `disk`/`ring`/`circ`/
  `spectro`/`sphere` → Circular) — drives which per-display fit knobs surface.
- `discover()` returns visuals **sorted by display label** (fixes menu order).
- `resolve_or_first()` falls back to the first visual for a bad config name.

Shipped visuals: `bars`, `fire`, `wave` (+ `_common.wgsl` shared prelude).

---

## 7. Menu / Right-Click UX (`menu.rs`)

- **Decision — use a `walker --dmenu` popup, not the GtkBuilder XML menu.**
  The earlier GtkBuilder XML `menu-file` path triggered a GTK assertion crash
  in Waybar 0.15 (`gtk_menu_popup_at_pointer: assertion 'GTK_IS_MENU'`).
- `omaviz menu` (right-click, no `--out`) builds the item list with icons
  (`▮` bars, `◉` circular, `•` other) + preselects the current visual, pipes it
  to `walker --dmenu --placeholder omaviz --current <viz> --exit`, and dispatches
  the chosen visual via `omaviz select mini <name>`.
- **Fix:** `walker` rejects `--prompt` and uses `--index` for output format, not
  preselection. The broken invocation (`--prompt omaviz --index <n>`) made
  `omaviz menu` exit immediately → right-click did nothing. Correct flags:
  `--placeholder`, `--current <value>` (preselect), `--exit`.
- `omaviz menu --out <file>` still regenerates the GtkBuilder XML artifact
  (kept for debugging/install), but it is **not** wired into Waybar.
- All menu actions use the **absolute binary path** (`/home/kishan/.local/bin/omaviz`)
  because Waybar's environment does not have `~/.local/bin` on `PATH`. The
  `omaviz_bin()` helper honors an `OMAVIZ_BIN` env override (used by tests).

---

## 8. Mode / Lifecycle (`mode.rs`)

Modes: `off` (paused, bar dimmed), `mini` (Waybar bars), `desktop` (floating
window), `full` (fullscreen). Stored in `/run/user/1000/omaviz/omaviz.mode`.

- `toggle` cycles **Mini ⇄ Desktop** (left-click).
- `off` pauses; `quit` stops the daemon, removes the Waybar module, hides the bar.
- `start` (app-launch) ensures daemon + Waybar module, resumes to Mini.
- `add_waybar_module()` splices the module into `config.jsonc` with the absolute
  path and the popup right-click (`on-click-right: omaviz menu`), and **does not**
  emit the crashing `menu-file` keys.
- `refresh_waybar()` sends `SIGUSR2` to Waybar to reload (used after config
  changes); the bar module itself is never restarted as a standalone process.

### CLI surface
```
omaviz daemon [--debug] [--seconds N]     # capture + broadcast (systemd)
omaviz mini  [--width N]                  # waybar JSON module
omaviz desktop | full                    # GPU windows
omaviz settings                          # egui panel
omaviz visuals                           # list shaders
omaviz config                            # print config path
omaviz mode [off|mini|desktop]           # get/set mode
omaviz toggle | off | quit               # lifecycle
omaviz menu [--out FILE]                 # right-click popup / XML
omaviz sensitivity +0.1 | -0.1 | 1.5     # scroll wheel
omaviz select <mini|desktop|full> <viz>  # set a visual
omaviz window-closed | window-close      # desktop window close handshake
omaviz start                             # app launch entry point
```
`--debug` enables ASCII-meter daemon logging and propagates via `OMAVIZ_DEBUG`
to child processes.

---

## 9. Configuration (`config.rs`, `~/.config/omaviz/config.toml`)

Key sections:
- `[audio]` — `sensitivity`, `smoothing`, `bands` (shared defaults; modes inherit
  unless overridden with a negative/invalid value).
- `[desktop]` / `[full]` / `[mini]` — `visual`, `fps`, `sensitivity`, `smoothing`,
  `bands`, and an `extra` table for per-display fit.
- `[mini.extra]` — `density`, **`mini_gain` (2.2)**, **`mini_floor` (0.15)** for the
  tiny bar.
- `[palette]` — `source = "auto"` (resolves Omarchy theme accent) or `manual`
  with explicit `low`/`high`/`bg`/`opacity`.
- `[visuals]` — per-visual knob overrides keyed by visual name.

Inheritance: a mode with `sensitivity < 0` / `bands == 0` falls back to the
shared `[audio]` value. `set_visual_all()` sets the same visual across all three
modes (the visual choice is shared; only fit differs). `visual_param()` returns
the override else the shader default, **clamped** to the param's min/max.
`reset_visual()` clears overrides.

---

## 10. Waybar Integration (`config.jsonc` + `install.sh`)

- `install.sh` writes a `custom/omaviz` module with **real newlines** (a prior
  bug wrote literal `\n` escapes, corrupting the JSON and preventing Waybar from
  starting at all — see §12).
- Module keys: `exec` (absolute `omaviz mini --width 18`), `return-type: json`,
  `format: {}`, `on-click` (toggle), `on-click-right` (`omaviz menu`), scroll
  wheel → `sensitivity +/-0.1`.
- `add_waybar_module()` and `install.sh` keep the module's object + the
  `modules-right` array reference in sync (brace-aware edits).

---

## 11. Rendering (`render.rs`, WGSL shaders)

- wgpu renderer; the shared prelude (`_common.wgsl`) + per-visual fragment stage.
- Per-display fit knobs are uploaded as uniforms (`knobs2` carries
  `full_detail`, `full_quality`, `mini_simplify`, …) so shaders can read mode
  nuance (bar visuals fill the small bar height; circular visuals use full room).
- `Renderer::set_visual()` hot-swaps the active shader; `apply_config()` applies
  live config changes.

---

## 12. Known Failure Modes & Fixes (root-cause log)

These are the issues that produced the user's "nothing works" report, with the
verified fixes.

1. **Waybar never started (config corruption).** `install.sh`'s module template
   used escaped `\\n`, collapsing the module into one invalid JSON line in
   `config.jsonc`. Waybar aborted on parse → entire bar (and omaviz) absent.
   *Fix:* module template uses real newlines; verified the file parses
   (`json5`). (`mode.rs`'s `add_waybar_module` already used correct newlines.)

2. **Right-click menu did nothing.** `omaviz menu` passed `walker --prompt …`
   which walker rejects (`Unknown option --prompt`); the process exited before
   showing anything. *Fix:* `--placeholder` / `--current` / `--exit`.

3. **Mini flat / desktop window looked empty.** Two contributors:
   - The capture works only with the running daemon + real audio; short-lived
     test daemons/silence read `e=0.000`. *Fix:* rely on autoconnect (not
     `target.object` pinning); the user's normal daemon + audio produces
     `class:"active"` with energy.
   - The config lacked `mini_gain`/`mini_floor`, so bars stayed at the lowest
     glyph. *Fix:* added `mini_gain = 2.2`, `mini_floor = 0.15` → bars visibly
     raised with a floor.

4. **Left-click "doesn't open" the desktop window.** The window *does* spawn
   (verified mapped + visible via Hyprland); it only looked empty because of the
   capture/timing above. With audio it renders a live visualization.

5. **GtkBuilder XML menu crash.** `menu-file` in Waybar 0.15 hits a GTK assertion.
   *Decision:* abandoned XML menu for the `walker --dmenu` popup.

6. **`debug()` duplicate.** `main.rs` had both `mod debug;` and a free
   `debug()`, and a dead `src/debug.rs`. *Fix:* removed the duplicate; `main.rs`
   owns `debug()`.

---

## 13. Testing

- **Unit tests** (`#[cfg(test)]` in `config.rs`, `visual.rs`, `dsp.rs`, `ipc.rs`,
  `menu.rs`): defaults/inheritance, shared-viz (`set_visual_all`),
  param clamping/reset, discovery + sort, DSP silence/tone, frame
  encode/decode/round-trip, menu XML validity + absolute paths.
- **CLI integration tests** (`tests/cli.rs`): `visuals` list, `mini` emits valid
  Waybar JSON, `mode` round-trip — driven as subprocesses via
  `CARGO_BIN_EXE_omaviz`.
- Run: `cargo test` (unit) and `cargo test --test cli` (integration).
- **Constraint:** GPU-free verification only. The agent must **never launch
  Waybar or any GPU-surface process** (doing so has crashed the Hermes desktop
  twice). Waybar restarts are left to the user; the bar module reloads via
  `SIGUSR2` only.

---

## 14. Operational Constraints (hard rules)

- **Never launch Waybar / GPU surfaces from the agent.** Backgrounding `waybar`
  crashed Hermes twice. All Waybar restarts are the user's action.
- **Absolute binary paths everywhere** in Waybar (env lacks `~/.local/bin`).
- **No GTK**; use `walker` for popups and `egui` for the settings panel.
- **Shaders are data** — drop-in WGSL, no rebuild to add a visual.
- Capture is **sink-monitor only** (system playback, not mic).

---

## 15. Summary of Decisions

| Topic | Decision |
|-------|----------|
| Right-click menu | `walker --dmenu` popup (icons + preselect), not GtkBuilder XML |
| Capture target | Autoconnect sink monitor (`STREAM_CAPTURE_SINK`); do **not** pin `target.object` |
| Settings panel | `egui` Split Panel, Omarchy-themed, Save/Cancel footer, per-viz Reset |
| Visual selection | Shared across modes; only per-display *fit* differs |
| Mini visibility | `mini_gain` + `mini_floor` in `[mini.extra]` |
| Config corruption | `install.sh` writes real newlines; `json5`-validated |
| GPU safety | Agent never launches Waybar/GPU surfaces |
| Shaders | Data-driven WGSL, discovered at runtime |
