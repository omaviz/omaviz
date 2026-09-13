# omaviz — Known Issues

## High Priority

### #1 ~~Settings panel toggles~~ ✅ Fixed (v7.7)
Writes go through `BarWidget.writeVizOption()` → writable FileView + immediate local config update (same proven pattern as the desktop-active flag). `Toggle`/`PanelSlider` from the shell kit.

### #4 ~~Right-click / desktop toggle behavior~~ ✅ Fixed (shared-flag)
- Right-click removed from mini; double-click mini or preview opens desktop
- Mini visibility now driven by shared `config desktop.active` flag —
  works from bar, app launcher, and keybind alike
- Desktop.qml self-claims `active=true` on open, writes `false` + `Qt.quit()` on close
- `onClosing → Qt.quit()` fixes the zombie-process loop (killactive only closed the window, process lingered, mini stayed hidden)
- App launcher fixed: old `Exec=omaviz start` pointed at a CLI that no longer exists → now `quickshell -p …/Desktop.qml`
- Keybinds fixed: `SUPER+V` launches Desktop.qml directly (dead `omaviz desktop/full/settings` CLI removed)

### #5 ~~Settings panel needs more options~~ ✅ Implemented (v7.7)
- **Peaks:** on/off Toggle — white peak-hold markers on mini, preview and desktop
- **Peak fall speed:** slider (0 holds, 1 falls fast), shown only when Peaks on
- **Spikes:** on/off Toggle — dense thin gapless flame spikes (~2px, Winamp thin-bar look); auto-enables Fire on select, auto-disables on deselect
- **Fire:** on/off Toggle — red flame gradient from the base, all surfaces (low end kept luminous so quiet bars stay visible on dark containers)
- **Splits:** renamed **Stacks** (preview/desktop only — segments need height to read, mini exempt)
- Fire uses one container-shared vertical gradient (short bars stay red, only tall bars reach yellow-white); stack segments sample the ramp per block
- Dense upsampling uses linear interpolation so neighboring bars blend instead of moving in lockstep
- Spikes+Fire toggle coupling done as a single multi-key write (sequential setTexts raced and the second clobbered the first — that was the stuck-SPIKES bug)
- All write `desktop.*` keys live: mini reflects next frame, preview immediately, open desktop within ~100ms
- Engine feeds: bar 128 bands (mini→32, preview→64 via max-downsample), desktop 256 (near 1:1 with dense spikes). Detail comes from source bands, not interpolation.
- Spike peak caps are 1px hot ticks (#ffe9a8); 2px blocks swallowed 2px bars.

---

## Medium Priority

### #2 Theme changes not propagating
Polling Timer reads every 500ms but live theme changes untested. May not detect external config edits.

### #3 Desktop CPU usage
Canvas-2D heavy (~36% observed). NOTE: no 15fps throttle exists in current code — engine emits at 60Hz (see #13), preview polls at ~30fps. Throttle still to be implemented.

### #6 Engine band count uneven across surfaces
Desktop already spawns `--bands 64` and preview renders 64; mini uses config `bands` (32). Remaining work: make mini band count follow suit or expose per-surface setting (see #14 for validation gap).

### #7 No multi-channel audio support
Engine outputs single `bands` array. No support for multiple instruments/streams.

### #8 Theme-aware backgrounds
Mini/desktop backgrounds should adapt to light/dark theme for better color visibility.

### #9 ~~Peaks only on preview/desktop, not mini~~ ✅ Fixed (v7.7)
Mini now has its own peak-hold markers (white 2px ticks + 60ms decay timer, same falloff mapping as VisualCanvas). All three surfaces honor the Peaks toggle.

---

## Low Priority

### #10 No engine crash fallback
Engine retry exists, no user-visible error state.

### #11 VisualCanvasGL.qml unused
Legacy GL renderer in repo, not used by default.

### #12 Engine shows frozen bars when PipeWire capture dies (high)
`main.rs` keeps re-emitting the last cached chunk forever — `last` is never cleared and nothing timestamps arrivals. If the capture thread errors (server restart, suspend), the mini shows frozen mid-motion bars instead of silence. Fix: timestamp last chunk, emit `silent:true` frame after ~2s without data.

---

## Medium Priority (review finds, 2026-09-13)

### #13 Engine emits duplicate 60Hz frames with no new audio
`main.rs` re-analyzes the same cached samples and flushes a frame every 16ms tick regardless of new data — 60 identical JSON lines/sec for QML to parse and repaint. Feeds #3 CPU. Fix: emit only on fresh chunk, or cap idle rate to ~30Hz.

### #14 `--bands` CLI value unvalidated
`bands=0` → `total / 0` = NaN energy → `build_frame` prints `NaN`, invalid JSON the plugin silently skips (dead mini, no error). Huge values → stdout flood. Fix: clamp to 4..=256 with error otherwise.

### #15 Dead pause machinery still live in code
`paused` / `detachedRunning` / `detachProc` / `Model.isPaused` remain wired (detach() still toggles them) though pause was removed and visibility moved to `desktopLive`. Next person to touch visibility may re-bind the wrong signal. Fix: delete the pause path entirely.

### #16 Two FileViews whole-file-write the same config
BarWidget (`detachConfigWrite`) and Desktop (`cfgWrite`) both `setText` the entire file — last-writer-wins on possibly stale cached text can resurrect a cleared flag. Windows are small today but the race is real. Fix: single-writer discipline (only the window writes its own keys) or merge-on-write with fresh reload before setText.

---

## Low Priority (review finds, 2026-09-13)

### #17 build.sh hard-fails on missing `qsb` for the unused GL shader
`exit 1` when no qsb and no prebuilt `visual.qsb` — but the GL renderer is unused (#11). A missing Qt tool shouldn't break engine builds. Fix: warn and continue.

### #18 Version + spec drift
`manifest.json` says 2.0.0 while tags are at v7.6.3; APPLICATION_SPEC.md doesn't document the shared-flag/heartbeat design. Fix: sync version, add spec section.

### #19 plugin/tests/ is empty and Model.js can't run under node
`.pragma library` fails node syntax check, so no JS harness can import Model.js as-is. Fix: either a qml-compatible test setup or remove the dir to stop implying coverage.

### #20 frame.rs interpolates `source` into JSON unescaped
A quote/backslash in the source name would emit invalid JSON the plugin silently drops. Internal-only values today, so latent. Fix: escape or use serde_json.

### #21 Engine retry gives up after 10 tries, silently (medium)
`BarWidget.qml` `spectrumProc.onExited` retries at most 10× (~15s), then the mini is dead until shell restart — no user-visible state. Extends #10. Fix: retry indefinitely with backoff + show dimmed/silent state.

### #22 `[mini] gap` config doesn't change rendered spacing (medium)
`implicitWidth` uses `config.gap`, but the rendered bars use hardcoded `gapPx: 1` and derive `slotWidth` back from the container width — the two width formulas disagree, so gap/width intent isn't honored (same class of bug as the earlier bar-overspill fix). Fix: single shared formula, rendered gap bound to config.

### #23 Preview repaints ~30/s unconditionally (medium)
`Panel.qml` reassigns preview bands every 33ms whether or not a new frame arrived, forcing repaint + peak churn in the bar process. Feeds #3. Fix: only assign on changed frame (sequence counter or identity check).

### #24 colorSync palettes ignore theme colors (low)
`VisualCanvas.fillFor` hardcodes blue/purple/orange ramps when `colorSync=true`, while the `false` path uses `themeBottom` — incoherent with the theme-sensitivity goal. Fix: derive all ramps from theme colors or drop the dead branches.

---

## Summary

| Priority | Count |
|----------|-------|
| High     | 3     |
| Medium   | 12    |
| Low      | 8     |
| **Total**| **23** |
