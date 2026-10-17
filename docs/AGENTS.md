# AGENTS.md — rules for AI agents working in omaviz

Read this before touching anything. It encodes hard-won failures; every
rule below cost a debugging session.

## Verification discipline (GPU-free, mandatory)

- **NEVER launch the wgpu/Desktop GPU surface or `quickshell -p` windows
  from long-lived agent sessions** — use `timeout N quickshell -p ...`
  for launch smoke tests, then kill. Verify through:
  - `npm run lint:qml` (Qt 6 explicitly; must be exit 0 before install)
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
   500ms, Desktop every 250ms. Keep the polls.
3. **`FileView.setText` is async** — never write-then-quit instantly
   (Desktop delays `Qt.quit()` 300ms); never two `setText`s off one base
   text (use `writeVizOptions` multi-key single write).
4. **Mini stays active beside Desktop** (user requested simultaneous surfaces).
   `desktopLive` only tracks the popout, using `desktop.active` in desktop-state.toml +
   a 2s heartbeat lease (6s expiry). Do NOT gate on process state, do NOT clear the
   flag from the bar based on `detachProc` (fights launcher-opened windows).
5. **One renderer**: `VisualCanvas.qml` owns the shared API/physics; `renderer/geometry.cpp` owns
   shared native GPU drawing. Never add
   a second bar renderer (a duplicated Repeater was deleted for this reason).
6. **Config writes** go through `writeVizOption(s)` / `writeEngineOption`
   (engine flags need process restart). SettingsDocument bases writes on its polled reader and SettingsQueue;
   never on the write-only FileView cache.
7. **Peak physics**: Winamp hang + ×1.05 accelerating fall. Don't revert to
   linear decay. Preserve the shipped `linear_fall` default; do not change physics during refactors.
8. **Frame protocol**: `bands, energy, beat, silent, source, t` + separate
   `{wave:[...]}` lines. QML parsers must tolerate missing keys (old frames).

## Workflow

- Track each fix with version + evidence (commit message + tag).
- `./install.sh` (not `--build`) after QML-only changes; `--build` after
  engine changes. `install.sh` restarts the shell itself.
- Commit + tag per user request (minor bumps: manifest + spec versions).
- Keep `APP_SPEC.md` and `README.md` in sync with behavior changes.
- Don't launch/restart quickshell or the shell from agents — tell the user
  to run `omarchy-restart-shell` if a manual reload is ever needed.

## Release review lessons (2026-10-11)

1. Read full `git status` as well as the dirty-file list before branch operations; this checkout had an unfinished rebase. Preserve existing work and use a separate worktree when needed; exclude local `backups/` from release commits.
2. Keep these instructions under `docs/`: marketplace preflight explicitly rejects a root `AGENTS.md`.
3. `npm run verify` covers JS, installer safety, and Rust; native CTest, native controls, and real QML component I/O are separate gates.
4. Offscreen component tests can fail at process launch inside a sandbox. Read the failure and use the normal approval path; do not classify a launch failure as an application regression.
5. `tests/native-controls/generate.py` uses the host Omarchy `PanelSlider.qml`. A generic Linux CI runner cannot run it without that dependency.
6. Test Siri → Strings → full spectrum transitions using real `EngineFeed` instances. Their 6/16/full band layouts and 1/128 waveform lengths differ.
7. Capture-loss frames must zero waveform data as well as bands, and retain the selected compact layout. A silent flag alone leaves stale geometry.
8. Sanitize nonfinite PCM before FFT/waveform processing; protocol serialization must also escape every JSON control character.
9. Warm up native comparison surfaces before fixed timelines. Scene startup can coalesce submissions; inspect frame/profile logs when parity unexpectedly fails. A retry alone is not proof of a fix.
10. Build and test the native module and its shaders. Rust reproducibility does not verify the bundled Qt library; native CI is compatibility coverage, not reproducible-build attestation.
11. Local Docker may exist without daemon permission. Use the CI-built engine artifact and verify its digest instead of labeling a local build reproducible.
12. Release from merged master, wait for exact-commit checks, then tag. The marketplace form must target current upstream HEAD; use the shared generator and duplicate marker, and distinguish submitted from marketplace-approved.
13. Keep performance claims separate from image parity. The retained Spectrum experiment has not demonstrated its 50% target, and stacks can increase GPU work.
14. For cheaper delegated verification, specify exact paths/commands, expected evidence, success checks, short output, and hard stop conditions; personally verify decisive results. Do not delegate open-ended diagnosis or visual judgment.
15. Qt's cached FastBlur can retain artwork across mode changes; unload its entire Loader when the artwork backdrop is inactive, and test Bars → Strings with a real QML Loader.
16. Stack rows must remain visibly distinct from continuous Bars. Keep a one-scale-unit gap within each four-scale-unit pitch in both shader and CPU paths; inspect a screenshot as well as comparing renderer parity.
17. Strings can use a full desktop surface without changing Siri/Waves' 3:1 silhouette; test viewport bounds at normal, wide, tall, and minimum sizes.
18. Check `journalctl --user` after a live reinstall: static QML lint did not catch `Style.spacing.small`, which was undefined at runtime. Use the host's valid `Style.space(...)` API for that control.
19. For Strings, use the user-provided Plexamp frame as the visual target: independent high-frequency warm loops wrap a pipe of uniform radius along its length, its height expands with music, some outer strands are softly defocused, and a few broad blue strands sit in front. A mirrored, center-pinched almond looked unlike the reference; inspect playback frames and measure rotation, audio response, and height expansion.

20. The unqualified `/usr/bin/qmllint` on this host is Qt 5. Use the Qt 6-aware `npm run lint:qml` gate. Syntax checks do not prove runtime property resolution; `tests/desktop.cjs` instantiates the production Window with isolated settings and disabled capture to verify fullscreen, Escape, closing, and saved dimensions.
