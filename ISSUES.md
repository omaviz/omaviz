# omaviz — Known Issues

## High Priority

### #1 Settings panel toggles
Peaks toggle and Peak fall buttons may not write to config. `sed` Process approach untested in Quickshell sandbox.

### #4 ~~Right-click / desktop toggle behavior~~ ✅ Fixed (shared-flag)
- Right-click removed from mini; double-click mini or preview opens desktop
- Mini visibility now driven by shared `config desktop.active` flag —
  works from bar, app launcher, and keybind alike
- Desktop.qml self-claims `active=true` on open, writes `false` + `Qt.quit()` on close
- `onClosing → Qt.quit()` fixes the zombie-process loop (killactive only closed the window, process lingered, mini stayed hidden)
- App launcher fixed: old `Exec=omaviz start` pointed at a CLI that no longer exists → now `quickshell -p …/Desktop.qml`
- Keybinds fixed: `SUPER+V` launches Desktop.qml directly (dead `omaviz desktop/full/settings` CLI removed)

### #5 Settings panel needs more options
Add controls:
- **Peaks:** on/off — if on, show fall speed slider (0=instant, 1=slow)
- **Spikes:** on/off — if on, render bars with sharp top edges (not rounded rectangles) like Winamp
- **Fire:** on/off — if on, bars bottom starts red and fades to theme color

---

## Medium Priority

### #2 Theme changes not propagating
Polling Timer reads every 500ms but live theme changes untested. May not detect external config edits.

### #3 Desktop CPU usage
Canvas-2D at ~36% CPU. Not ideal but acceptable at 15fps throttle.

### #6 Engine limited to 32 bands
Engine supports `--bands N` but plugin hardcodes 32. Desktop/fullscreen would benefit from 64+ bars for denser spectrum.

### #7 No multi-channel audio support
Engine outputs single `bands` array. No support for multiple instruments/streams.

### #8 Theme-aware backgrounds
Mini/desktop backgrounds should adapt to light/dark theme for better color visibility.

### #9 Peaks not confirmed
Mini working but peak-hold markers not explicitly verified by user.

---

## Low Priority

### #10 No engine crash fallback
Engine retry exists, no user-visible error state.

### #11 VisualCanvasGL.qml unused
Legacy GL renderer in repo, not used by default.

---

## Summary

| Priority | Count |
|----------|-------|
| High     | 2     |
| Medium   | 5     |
| Low      | 2     |
| **Total**| **9** |
