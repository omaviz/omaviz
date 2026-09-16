# omaviz — if you liked Winamp, you'll love omaviz even more

The spectrum analyzer you stared at for hours in 1999 — reborn as a
native citizen of your Omarchy desktop. Live bars in your waybar, a full
desktop visualizer window, and an oscilloscope that dances to whatever
is playing. Same soul, zero nostalgia tax: buttery Canvas rendering,
theme-aware, and configured with two clicks.

![version](https://img.shields.io/badge/version-8.0.3-amber) ![license](https://img.shields.io/badge/license-MIT-blue)

## Why omaviz

- **It lives where you look.** No separate app to open — the visualizer
  is always there, in the bar, pulsing with your music, your calls,
  your game.
- **One click to tweak, double-click to go big.** The settings panel
  shows a live preview of every change. Double-click it and the same
  visualization explodes onto a borderless desktop window.
- **Your colors, everywhere.** Follow the Omarchy theme automatically,
  or dial in your own From → To gradient — mini, preview, desktop and
  waveform all stay in sync.
- **Deaf to players, loyal to sound.** It listens at the PipeWire monitor,
  so it visualizes *everything* — Spotify, browser, games, calls, local
  files. No player plugins, no per-app setup, no exceptions.
- **Winamp physics, not a slideshow.** Peak-hold markers with accelerating
  fall, instant-rise linear mode, flame gradients, segmented stacks —
  the motion language your muscle memory already knows.

## The tour

| | |
|---|---|
| ![desktop window with artwork backdrop](docs/screenshots/Desktop-window-with-artwork.png) | ![fire flame gradient](docs/screenshots/fire.png) |
| *Desktop window + artwork backdrop + floor reflection* | *Fire: red base igniting into your custom tip* |
| ![stacked bars](docs/screenshots/Stacked-bars.png) | ![oscilloscope waveform](docs/screenshots/oscilloscope.png) |
| *Stacks: segmented Winamp-style bars* | *Oscilloscope: true time-domain waveform* |
| ![custom color tones](docs/screenshots/Custom-colors.png) | ![theme following](docs/screenshots/Theme-enabled.png) |
| *Bar color: presets or your own From → To tones* | *Theme mode tracks the Omarchy accent live* |

## Features

- **Mini** — 32 bars in the bar (128-band engine feed, max-downsampled),
  with a dotted-skin backdrop and a B&W Mono mode for tiny sizes
- **Spectrum** — peaks + fall speed, dense Spikes, Fire flame gradient,
  Winamp Stacks, floor-mirror Reflection, album-art backdrop
- **Oscilloscope** — true 128-point time-domain waveform, adjustable
  thickness, follows your colors
- **Bar color** — theme-dominant by default (tracks Omarchy theme
  switches live), or custom From → To tones via presets or hex
- **Motion** — exponential easing by default, Winamp-style linear fall
  on demand, adjustable sensitivity
- **Robust** — shared-flag + heartbeat desktop lifecycle (no zombies),
  engine auto-retry, one shared Canvas renderer everywhere.

## Install

Requires Omarchy (Quickshell) + PipeWire. Zero-build: the engine binary
ships committed, so no toolchain is needed — only `./install.sh --build`
needs `cargo`.

```bash
cd ~/omaviz
./install.sh            # zero-build: uses the committed engine binary
./install.sh --build    # rebuild engine from Rust source first
./uninstall.sh          # remove plugin (+ launcher); --purge also config
```

Requires: Omarchy (quickshell), PipeWire, `cargo` (only for `--build`).

Single-click the mini for settings · double-click (or `SUPER+V`) for the
desktop window · close it and the mini returns by itself.

## Mini

Thirty-two live bars riding in your bar, fed by the 128-band engine —
with a dotted-skin backdrop and a B&W Mono mode for tiny sizes.
Single-click the mini for the settings panel below, double-click it
(or `SUPER+V`) for the desktop window:

![settings panel with mini in the bar](docs/screenshots/Mini.png)

## Engine

The Rust engine lives *inside* the plugin and is fully managed —
spawned, restarted and retired by the bar widget itself. There is
nothing to configure, no service to enable, no socket to babysit:
install and it just runs. Rebuild from source only if you want to
hack on it (`./install.sh --build`).

```bash
omaviz-engine --bands 128 --fall-mode exp|linear --fft-size 2048 --wave
```

One JSON frame per line on stdout (`bands, energy, beat, silent, source,
t`) plus `{wave:[...]}` lines with `--wave`. Emits on fresh audio with a
5Hz heartbeat; explicit zero-silence 2s after capture death.

## Layout

Repo root **is** the plugin (`manifest.json` lives here, per the
marketplace rules) — dev-only baggage (`engine/`, `docs/`, scripts)
is excluded at install time:

```
manifest.json    # plugin identity (id, version, entry points)
BarWidget.qml    # bar mini + engine spawn + all config writes
Panel.qml        # settings panel (preview + options)
Desktop.qml      # detached window (standalone quickshell -p, NO qs.* imports)
VisualCanvas.qml # THE shared renderer (all modes, all options)
Model.js         # config parse/write, spectrum parsing
assets/ bin/ tests/  # launcher entry, COMMITTED engine binary, node tests
engine/          # Rust source: PipeWire capture → FFT → bands + wave frames
install.sh / build.sh / uninstall.sh
APP_SPEC.md  # full spec
```

Installs to `~/.config/omarchy/plugins/org.omaviz.visualizer/`.

## Docs

- `APP_SPEC.md` — architecture, config keys, lifecycle
- `docs/AGENTS.md` — rules for AI agents working in this repo

## Open source

> **Private by design.** No trackers, no analytics, no network calls —
> the engine reads your local audio, the panel reads local players, and
> nothing ever leaves your machine.

MIT-licensed and hackable end to end: QML surfaces, shared Canvas
renderer and the Rust PipeWire engine all live in this repo, with
`APP_SPEC.md` as the design record and tests for both sides
(`tests`, `cargo test`). Found a rough edge or a missing
Winamp-ism? Issues and PRs welcome — the tour screenshots above are
all taken from the live plugin, so what you see is what runs.
