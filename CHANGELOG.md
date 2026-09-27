# Changelog

## 8.4.0

Architecture and behaviour release. Engine output contract changed (raw bands);
the plugin ships a new shared physics module and a config store.

### Fixed
- **Theme palette / custom bar colours were ignored.** The bar body was filled
  with a gradient built from the Fire ramp in *every* mode, and that ramp's base
  is hardcoded deep red — so the base bar colour was always red no matter the
  theme or the selected custom colour. The body gradient now comes from the
  active palette (theme, or the custom From→To pair) unless Fire is on.
- **Faint audio produced no bars.** The renderer rendered `silent ? 0 : …`, and
  the engine reported `silent` whenever mean band energy fell below 0.02 — so
  any quiet passage hard-zeroed every bar. `silent` is now advisory only and
  never zeroes bars; the engine flags silence from the *loudest* band instead.
- **Bars vanished instantly instead of falling.** Motion is now a proper
  envelope: instant attack, rate-limited release.
- **Settings did not sync on the first try.** The panel's ON/OFF switch was
  bound to a non-observable `sharedConfig` shadow copy that was never updated
  on config load. It is now bound to the live config, and every config load
  flows through one `syncFromConfig()`.
- **Theme sync was silently off.** `colorSync` / `linearFall` / `reflect` were
  read with `=== "true"` while their defaults are `true`, so any config lacking
  those keys disabled them; the bootstrap TOML even wrote `color_sync = false`.
- **The mini widget failed to load entirely.** `VisualCanvas.qml` declared
  `property bool colorSync` twice — the QML engine rejects the whole component
  ("Duplicate property name" → "Type VisualCanvas unavailable"). `qmllint` does
  not flag this; a dedicated test now does.
- `loadFromTOML()` returned `undefined`, which blanked `root.config`.

### Added
- **Peak caps now hold.** A peak rides at its high-water mark for
  `peak_sustain_ms` (default 100) before falling with an accelerating speed
  (×1.05/frame) — the Winamp hang-then-snap.
- `Physics.js` — the bar/peak motion model, extracted so it is unit-tested and
  shared byte-for-byte by the mini, panel preview, desktop window and scope.
- `ModelStore.js` (renamed from `Model.js`) — config model plus a reactive store
  (`get` / `set` / `onChanged` / `loadFromTOML` / `toTOML` / `validate`).
- `gen=` audio source accepts `:amp=` for testing faint-signal handling.

### Changed
- The engine emits **raw** band magnitudes at ~60 Hz for every surface; all
  smoothing, fall-mode and peak physics moved to the renderer. `--fall-mode`
  was removed.
- The desktop window no longer decimates its feed to 30 Hz.
- Test suite: 92 JS + 40 Rust tests (physics, config store, QML syntax and
  architecture guards, and a suite that drives the committed engine binary).
  `npm test` works again; Node ≥ 24.
