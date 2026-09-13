# omaviz — Winamp-style audio visualizer for Omarchy

Live spectrum analyzer in your waybar: mini bars, settings panel with
preview, and a detached desktop window. One shared Canvas-2D renderer
(`VisualCanvas.qml`) drives all three surfaces — mini, preview, desktop —
so every option looks identical everywhere.

![version](https://img.shields.io/badge/version-7.14.1-amber) ![license](https://img.shields.io/badge/license-MIT-blue)

## Features

- **Mini** — 32 bars live in waybar (128-band engine feed, max-downsampled)
- **Settings panel** — live preview + grouped options (see below)
- **Desktop window** — 256-band feed, bottom-anchored, `SUPER+V`
- **Modes** — Spectrum bars or true Oscilloscopes (128-pt time-domain feed)
- **Winamp options** — Peaks + fall speed, Spikes (dense gapless flame),
  Fire (vertical red→white-hot gradient), Stacks (segmented bars),
  Linear fall, Dots backdrop, Reflection floor mirror
- **Theme-aware** — follows the live shell accent when `color_sync`, theme
  backgrounds on bar/panel
- **Robust** — shared-flag + heartbeat desktop lifecycle (no zombie windows),
  indefinite engine retry, stale-capture silence, validated CLI

## Install

```bash
cd ~/workspace/omaviz
./install.sh            # zero-build: uses the committed engine binary
./install.sh --build    # rebuild engine from Rust source first
./uninstall.sh          # remove plugin (+ launcher); --purge also config
```

Requires: Omarchy (quickshell), PipeWire, `cargo` (only for `--build`).

## Options (settings panel — single-click the mini)

| Section | Option | What it does |
|---|---|---|
| Mode | Spectrum / Oscilloscope | Dropdown; mini follows too |
| Spectrum | Peaks, fall speed, Spikes, Fire, Stacks, Linear fall | Bar look + motion |
| Oscilloscope | Line thickness | Waveform (follows Fire + Sensitivity) |
| Common | Dots, Reflection | Skin dressing, both modes |

Double-click mini or preview → desktop window. Close it (× or `Super+W`) → mini returns.

## Engine

```bash
omaviz-engine --bands 128 --fall-mode exp|linear --fft-size 2048 --wave
```

One JSON frame per line on stdout (`bands, energy, beat, silent, source,
t`) plus `{wave:[...]}` lines with `--wave`. Emits on fresh audio with a
5Hz heartbeat; explicit zero-silence 2s after capture death. 38 `cargo test`s.

## Layout

```
plugin/          # self-contained drop-in → ~/.config/omarchy/plugins/org.omaviz.visualizer/
  BarWidget.qml  # waybar mini + engine spawn + all config writes
  Panel.qml      # settings panel (preview + options)
  Desktop.qml    # detached window (standalone quickshell -p, NO qs.* imports)
  VisualCanvas.qml  # THE shared renderer (all modes, all options)
  Model.js       # config parse/write, spectrum parsing
engine/          # Rust: PipeWire capture → FFT → bands + wave frames
install.sh / build.sh / uninstall.sh
APPLICATION_SPEC.md  # full spec · ISSUES.md  # issue list · WINAMP_PARITY.md
```

## Docs

- `APPLICATION_SPEC.md` — architecture, config keys, lifecycle
- `ISSUES.md` — issue list (fixed archive + queue)
- `WINAMP_PARITY.md` — Winamp comparison + phased plan
- `AGENTS.md` — rules for AI agents working in this repo
