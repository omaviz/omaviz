# omaviz

Omarchy-native audio visualizer. One PipeWire sink-monitor tap → one shared DSP
daemon → three render modes + a settings panel.

## Status — all four requirements implemented and verified

| # | Requirement | State |
|---|---|---|
| 1 | Three modes: desktop window / fullscreen / waybar mini | **done** |
| 2 | Captures any audio playback (Plexamp, browser, anything) | **done** |
| 3 | Settings panel for selecting & tweaking visualizations | **done** |
| 4 | First-class, resource-friendly performance | **done** |

## Architecture

```
pipewire default-sink monitor   (STREAM_CAPTURE_SINK=true — catches Plexamp,
        │                        browsers, any app on the sink; no per-app work)
   [omaviz daemon]  FFT 2048/Hann → 32 log bands → attack-decay → beat detect
        │
        │  unix socket $XDG_RUNTIME_DIR/omaviz.sock, 16B header + f32 bands
        │
        ├── omaviz desktop    xdg_toplevel + wgpu
        ├── omaviz full       fullscreen + wgpu
        ├── omaviz mini       waybar custom module (JSON lines)
        └── omaviz settings   egui panel w/ live preview
```

The DSP runs **once** in the daemon. Every mode is a pure consumer, so running
all three at the same time costs one FFT, not three.

## Verified measurements

Real numbers from this machine, not estimates:

| Scenario | Cost |
|---|---|
| Daemon, music playing, 32 bands @ 60 Hz | **0.50% CPU** |
| Daemon, client attached | **0.40% CPU** |
| Daemon idle (no clients, silence) | **0.00% CPU, 2.5 MB RSS** |

Verified visually: desktop mode renders gradient spectrum bars; full mode goes
true fullscreen (2560x1440) with the wave ribbon; mini mode renders block-glyph
bars inside a real waybar 0.15 instance; settings panel reports
`daemon: connected` with a live preview strip.

## Usage

```bash
cargo build --release

omaviz daemon            # start the capture/DSP daemon (or use the systemd unit)
omaviz daemon --debug    # live ASCII spectrum, for sanity-checking capture
omaviz desktop           # small floating window
omaviz full              # fullscreen  (f toggles, q/Esc quits)
omaviz mini --width 14   # waybar module output
omaviz settings          # settings panel
omaviz visuals           # list installed visualizations
omaviz config            # show resolved config
```

## Performance design

- Single shared DSP pass; clients never compute their own FFT.
- `PresentMode::Fifo` (vsync) — never renders frames the compositor discards.
- Per-mode fps caps: mini 30, desktop 60, full 0 (= vsync).
- Silence gate: clients stop drawing after ~2s of quiet; the daemon skips the
  FFT entirely and drops to a 200 ms poll when no client is attached.
- Mini mode only writes a line when the glyphs actually change (waybar
  re-lays-out on every line).
- No CPU pixel work — all visuals are fragment shaders. No per-frame allocs.

## Visualizations

WGSL fragment shaders in `visuals/`, discovered at runtime — drop in a new
`.wgsl` and it appears in `omaviz visuals` and the settings dropdown with no
rebuild. `_common.wgsl` supplies the shared uniform block, vertex stage, and
`band_lerp()` / `palette()` helpers.

Search order: `~/.config/omaviz/visuals` → repo `visuals/` → `/usr/share/omaviz/visuals`.

Shipped: `bars`, `wave`. Mini mode has a deliberately limited set (`bars`, `vu`)
since it renders with text glyphs.

## Config

`~/.config/omaviz/config.toml`, written with defaults on first run. Edit via the
settings panel or by hand.

## Integration

Files in `integration/`:

- `waybar-module.jsonc` — the custom module block
- `waybar-style.css` — monospace styling + `.silent` dimming
- `hyprland.conf` — float/size/position rules + Super+V / Super+Shift+V binds
- `omaviz.service` — systemd `--user` unit for the daemon

```bash
systemctl --user enable --now omaviz.service
```

## Known constraints

- Requires `pipewire-rs` 0.10; **0.8 does not compile** against libpipewire 1.6.8.
- wgpu must request the adapter's real resolution limits — `downlevel_defaults()`
  caps textures at 2048px and hard-fails on 4K displays.

## Layout

- `src/capture.rs` — PipeWire stream, mono downmix
- `src/dsp.rs` — Hann FFT, log bands, dB scaling, onset detect
- `src/ipc.rs` — unix-socket frame broadcast
- `src/render.rs` — wgpu pipeline, shader discovery/hot-swap
- `src/client.rs` — winit window loop (desktop + full), frame reader
- `src/mini.rs` — waybar JSON module
- `src/settings.rs` — egui settings panel
- `src/config.rs` — TOML config
