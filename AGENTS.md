# AGENTS.md — rules for AI agents working in omaviz

Read this before touching anything. It encodes hard-won failures; every
rule below cost a debugging session.

## Verification discipline (GPU-free, mandatory)

- **NEVER launch the wgpu/Desktop GPU surface or `quickshell -p` windows
  from long-lived agent sessions** — use `timeout N quickshell -p ...`
  for launch smoke tests, then kill. Verify through:
  - `qmllint plugin/*.qml` (must be exit 0 before install)
  - `cargo test` in `engine/` (acceptance gate — writing tests ≠ done)
  - `./install.sh` + `journalctl --user` greps for omaviz errors
  - `grim` + vision screenshots of the bar (region `[2900,0,3840,140]`
    covers the mini on 3840-wide screens)
  - Engine stdout probes (`--source gen=tone` for rates/JSON validity)
- The bar/widget is **layer-shell**: `computer_use` and `hyprctl clients`
  cannot see it. Use grim. The settings panel is layer-shell too — you
  cannot click its toggles; flip the same config keys instead.

## Hard constraints

1. **Desktop.qml must NOT import `qs.*`** — standalone `quickshell -p`
   cannot resolve shell-context modules; the import kills the window on
   launch (`module "qs.Commons" is not installed`). This broke double-click
   once already.
2. **`FileView.watchChanges` is unreliable** — BarWidget polls config every
   500ms, Desktop every 100ms. Keep the polls.
3. **`FileView.setText` is async** — never write-then-quit instantly
   (Desktop delays `Qt.quit()` 300ms); never two `setText`s off one base
   text (use `writeVizOptions` multi-key single write).
4. **Mini visibility = `desktopLive`** (shared `desktop.active` flag +
   2s heartbeat lease). Do NOT gate on process state, do NOT clear the
   flag from the bar based on `detachProc` (fights launcher-opened windows).
5. **One renderer**: all visual work goes in `VisualCanvas.qml`. Never add
   a second bar renderer (a duplicated Repeater was deleted for this reason).
6. **Config writes** go through `writeVizOption(s)` / `writeEngineOption`
   (engine flags need process restart). Base writes on the polled views,
   never on write-only caches.
7. **Peak physics**: Winamp hang + ×1.05 accelerating fall. Don't revert to
   linear decay. Bar motion default is exp easing; `linear_fall` is opt-in.
8. **Frame protocol**: `bands, energy, beat, silent, source, t` + separate
   `{wave:[...]}` lines. QML parsers must tolerate missing keys (old frames).

## Workflow

- Fix one issue at a time from `ISSUES.md`; mark fixed with version + evidence.
- `./install.sh` (not `--build`) after QML-only changes; `--build` after
  engine changes. `install.sh` restarts the shell itself.
- Commit + tag per user request (minor bumps: manifest + spec versions).
- Keep `APPLICATION_SPEC.md`, `ISSUES.md`, `WINAMP_PARITY.md`,
  `README.md` in sync with behavior changes.
- Don't launch/restart quickshell or the shell from agents — tell the user
  to run `omarchy-restart-shell` if a manual reload is ever needed.
