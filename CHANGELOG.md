## 8.5.3 — Marketplace submission recovery

- Filter marketplace issue pages before returning data to the release helper, preventing buffer exhaustion in large catalogs while preserving duplicate detection.

## 8.5.2 — Panel consistency and release verification

- Match the heights of all paired settings controls and display the installed manifest version in the footer.
- Release the requested tag on manual runs, validate tag input, and include decorated changelog headings.
- Generate exact-commit marketplace verification links; optionally submit deduplicated requests with a dedicated credential.
- Run functional CI on every PR, including binary and metadata changes and avoid write-only attestations on pull requests.

## 8.5.1 — GPU exploration without renderer changes

- Report the actual compositing backend instead of the ineffective GPU switch.
- Add bounded software/native export comparisons for eight visualization modes.
- Document GPU options, hardware evidence, and parity/profiling requirements; keep production drawing and timing unchanged.

## 8.5.0 — Runtime ownership and functional verification

- Share engine lifecycle and protocol handling through EngineFeed; wait for process exit before restarting and bound failed starts.
- Move settings persistence into SettingsDocument and a pure serialized-write queue; remove the unused mutable JS store.
- Extract pure palette computation without changing drawing commands or physics.
- Replace source-string tests and wall-clock FPS thresholds with functional tests and bounded real QML I/O/process checks.
- Install only runtime files, excluding tests and development artifacts.

## 8.4.5 — Settings reliability and review fixes

- Isolate desktop leases from settings; serialize async saves and keep pending selections until acknowledged.
- Give Flame independent saved base/tip colors across mini, preview, and desktop.
- Respect explicit settings over legacy Stacks/Artwork aliases; correct preset highlighting and duplicate hex submissions.
- Escape TOML strings, preserve native value types, and accept inline comments.
- Use the resolved engine path in the bar; clamp FFT band ranges to prevent valid CLI combinations from panicking.
- Add behavioral persistence/palette regressions and FFT boundary coverage.

# Changelog

## Unreleased

Hardening pass across security, reliability, consistency and maintainability.

### Fixed
- **Hardcoded home path removed.** `ModelStore.js` no longer embeds a literal
  user home directory; paths resolve from `Quickshell.env` / `environment`, and
  the plugin dir derives from the module URL — so config + engine paths are
  correct for every user, not just the original developer.
- **TOML writes escape interior double-quotes** — a stray `"` in a value can no
  longer emit an invalid line that mis-parses the whole config file.
- **Desktop engine restarts now back off** (1.5s → 30s, reset on a healthy
  frame) instead of hot-looping when capture fails; the bar already did this.
- **`color_sync` is honored on every surface** (mini, preview, desktop) — it was
  hardcoded `true` on the preview and desktop canvases.
- **Oscilloscope honors Input gain.** The waveform amplitude now scales with
  `[audio] sensitivity`, so a quiet snippet is not a flat line.
- **No double physics step** after a resize: a paint resizes its buffers only and
  never advances the simulation.

### Settings panel redesign
- **Linear fall** stays in Advanced — still `writeEngineOption("linear_fall", …)`.
- Grouped **by intent** on one scrollable screen: **LOOK** (geometry + peaks +
  reflection), **COLOR** (mode + tones + direction + presets), **MOTION**
  (response + mono), **OSCILLOSCOPE** (thickness), **ADVANCED** (collapsed).
- **Flame is a colour mode**, not a geometry-coupled toggle — decoupled from
  Spikes; available as a chip and as a preset swatch.
- **New `bar_gradient_dir`** (`vertical` default / `horizontal`) adds a
  left→right gradient across the bar field (one shared gradient per frame).
- ADVANCED is collapsed, not a slide-out stage; the "Response" slider owns
  reactivity and its helper notes it scales the waveform with input gain.

## 8.4.4

Marker-driven operations can no longer be redirected outside the plugin folder.

### Fixed
- **A symlinked directory inside the plugin folder redirected a delete.** The
  scripts refused a symlinked plugin folder at the top level, but still resolved
  every component *below* it. Replacing `assets/` with a symlink to a user
  directory made the marker entry `assets/omaviz.desktop` delete that outside
  file during a managed update or an uninstall. Every marker entry is now
  resolved component-by-component and skipped unless it is provably contained —
  no absolute path, no traversal, no symlinked intermediate directory — so `rm`
  and `rmdir` can never reach outside the plugin folder.
- **The same boundary was open on the write side.** `rsync`, `chmod` and the
  launcher write all resolve intermediate components, so a linked subdirectory
  received our files outside the plugin folder. Installing into a plugin folder
  that contains a symlink is now refused outright; `--force` backs the whole
  directory up (`mv` moves a link, never through it) and installs fresh.

### Tests
- `tests/installer.test.sh`: 71 → 86 scenarios, covering the reported
  arrangement for both an uninstall and a managed update, the `--force` escape
  hatch, and a symlink at the leaf (unlinked, never followed). The new
  scenarios were confirmed to fail against the previous commit (4 failures)
  before the fix went in.

## 8.4.3

Installer hardening — every deletion and overwrite site in both scripts audited.

### Fixed
- **A foreign launcher could be deleted by path coincidence.** The legacy-entry
  check treated any `Exec=`/`TryExec=` line containing `plugins/…omaviz` as
  ours, so an unrelated entry running e.g.
  `/home/user/plugins/tools/omaviz-helper` was removed. Ownership now comes from
  the command alone — it must be a command this project actually shipped
  (`omaviz`), matched on the final path segment. No substrings, no path guesses.
- **Our own directories were removed wholesale.** The marker listed bare
  directories (`assets/`, `bin/`, `tests/`), so a managed update or an uninstall
  `rm -rf`'d them and took any file the user had placed inside with them. The
  marker now records individual files, removal is per-file, and directories are
  only `rmdir`'d when empty. A marker in the old format is handled
  non-recursively, so a stale marker cannot delete user files either.
- **Ownership is proven, not assumed.** A path is recorded in the marker only
  when the file installed there is byte-identical to its source counterpart, so
  a file the user added — or one of ours that they edited — is never claimed and
  therefore never removed.
- **Symlinks are no longer followed.** Both scripts refuse a symlinked plugin
  directory outright (every path is resolved relative to it, so a link would
  redirect deletions at its target), and a symlinked launcher is moved aside
  instead of written through — which previously overwrote its target file.
- **A `.git` file could leak into the plugin directory.** `rsync --exclude
  '/.git/'` matches only a *directory*; in a worktree or submodule `.git` is a
  file, so it was copied into the live plugin dir. The exclude is now `/.git`.
- Backup names are uniquified, so two backups in the same second cannot clobber
  each other.

### Tests
- `tests/installer.test.sh`: 35 → 71 scenarios, covering every case above —
  the reported path-coincidence case, files placed inside our own directories,
  old-format markers, symlinked plugin dirs and launchers, backup collisions,
  and a guard that nothing dev-only ships inside the plugin.

### Docs
- `docs/BUILD_ATTESTATION.md` named an engine digest from before the 8.4.0
  engine rebuild. It now states the digest actually shipped and the CI run that
  produced it.

### CI
- New `release.yml`: pushing a tag creates a verified, attested GitHub release.
  It refuses to publish unless the tag is on `master`, the manifest and package
  versions equal the tag, and the committed engine is byte-identical to a fresh
  pinned-container rebuild. The release carries the binary, `SHA256SUMS`, and a
  Sigstore attestation.

## 8.4.2

Installer safety — the second marketplace review blocker.

### Fixed
- **Install deleted a launcher it did not own.** `install.sh` removed
  `~/.local/share/applications/omaviz-desktop.desktop` (a legacy entry from
  very old omaviz versions) whenever the file merely *contained* the word
  `omaviz`, so a user-owned desktop entry that mentioned the plugin in its
  name, comment, or own command was destroyed on install/update. Ownership is
  now verified from the entry itself: it must be a `[Desktop Entry]` whose
  `Exec=`/`TryExec=` command is one omaviz actually shipped — the old `omaviz`
  CLI, or a path inside an omaviz plugin directory. Nothing is matched on the
  word appearing elsewhere in the file.
- **The check contradicted its own comment**, which claimed removal only "if it
  references the omaviz plugin path". Code and comment now agree.

### Tests
- `tests/installer.test.sh` gains 7 legacy-launcher ownership scenarios: a
  user file that mentions omaviz survives untouched, a stale `omaviz`-CLI
  entry is removed, a plugin-path entry is removed, a lookalike command
  (`omaviz-notes-editor`) is not matched, and an absent file is a clean no-op
  (42 scenarios total).

## 8.4.1

Installer/uninstaller safety — resolves the open marketplace review blocker.

### Fixed
- **Uninstall deleted files omaviz does not own.** `uninstall.sh` treated the
  presence of `.omaviz-managed` as ownership of the whole plugin directory and
  `rm -rf`'d it, so files a user had placed there survived a managed update but
  were destroyed on uninstall. Removal is now **marker-scoped** — symmetric
  with `install.sh`'s managed update — and the directory is removed only if it
  is empty afterwards; anything foreign is kept and listed.
- **Uninstall invoked a destructive manager command.** `omarchy plugin remove`
  falls back to `rm -rf "$PLUGIN_DIR"` for git-managed installs (which is what
  a marketplace install always is, since the repo is cloned), so it would have
  deleted unmanaged files regardless. It is replaced by
  `omarchy plugin disable`, which unloads the plugin without touching files.
- **The management marker was incomplete.** `rsync` also installed
  `package.json` and `.gitignore`, which the marker never listed, so even a
  pristine install left files behind. Both are now excluded from the installed
  set (repo metadata, not runtime), so an installed directory matches its
  marker exactly and uninstalls cleanly.

### Changed
- Marker validation is **all-or-nothing in both scripts**: every line is
  validated before anything is deleted, so a corrupt or hostile marker (empty
  line, `..` traversal, absolute path) refuses without a partial delete.
  `install.sh` and `uninstall.sh` now share the same `validate_marker` /
  `remove_managed_paths` helpers and cannot drift apart.
- New `tests/installer.test.sh` (35 scenarios, wired into CI) runs the real
  scripts against a throwaway `$HOME` with stubbed omarchy commands.

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
