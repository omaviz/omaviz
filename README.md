# omaviz

Omarchy-native audio visualizer. PipeWire sink-monitor tap → shared DSP daemon → three render modes.

## Status

| Step | Item | State |
|---|---|---|
| 1 | PipeWire capture → FFT → bands/beat, `--debug` ASCII meter | **done, verified on real audio** |
| 2 | Desktop-mode wgpu client (2 shaders) | next |
| 3 | TOML config + hot reload | pending |
| 4 | Waybar mini module | pending |
| 5 | Fullscreen mode + Hyprland keybind | pending |
| 6 | Settings GUI (GTK4/libadwaita) | pending |
| 7 | Idle/silence gating, perf pass, PKGBUILD | pending |

## Architecture

```
pipewire default-sink monitor  (STREAM_CAPTURE_SINK=true — catches Plexamp,
        │                       browsers, anything on the sink)
   [omaviz daemon]  FFT 2048 / Hann → log bands → attack-decay smoothing → beat
        │
        ├── desktop client   (xdg_toplevel, wgpu)
        ├── fullscreen client (same binary --fullscreen)
        └── bar widget       (waybar custom module)
```

DSP runs **once** in the daemon; clients are pure renderers consuming the same frames.

## Verified numbers

- Live capture from default sink monitor: `capturing rate:48000 channels:2`
- 32 log bands, 60 Hz analysis, release build: **0.50% CPU** of one core with music playing
- Silence gate at `energy < 0.02` (drives future render suspension)

## Run

```bash
cargo build --release
./target/release/omaviz --debug            # live ASCII spectrum
./target/release/omaviz --bands 64 --fps 30
./bench.sh                                 # CPU measurement
```

## Layout

- `src/capture.rs` — PipeWire stream, f32 mono downmix
- `src/dsp.rs` — Hann-windowed FFT, log-spaced bands, dB scaling, onset detect
- `src/main.rs` — daemon loop, frame pacing, debug meter
