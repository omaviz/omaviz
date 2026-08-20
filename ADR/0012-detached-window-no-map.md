# ADR-0012: Detached desktop window never maps (T-018) — wrong Window base type

| | |
|---|---|
| **Status** | Accepted (to implement in v7.6.x) |
| **Date** | 2026-08-19 |
| **Author** | architect (@architect) |
| **Task** | T-018 (roadmap #23) |
| **Applies to** | `plugin/Desktop.qml` — root `Window` (lines 1, 14) |
| **Supersedes** | none |
| **Superseded by** | none |

## 1. Context

`Desktop.qml` is launched as a **standalone Quickshell config** via
`quickshell -p Desktop.qml` (from `BarWidget.detach()`). Its header:
```qml
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "Model.js" as Model
...
Window {                       // line 14
  id: win
  visible: true
  flags: Qt.Window | Qt.WindowStaysOnTopHint
  ...
}
```
Production launch: pid 9927 (Desktop.qml) + 9948 (its engine) run, but the compositor
(Hyprland) shows **no mapped omaviz window**. The tester's own harness Window *did*
map (seen at pid 80790) — so this is not a generic "window never maps" failure; it
is specific to this `Desktop.qml` launch.

## 2. Root cause (confirmed from the production log)

`Desktop.qml` imports **both** `QtQuick` (which exports `QtQuick.Window`) and
`Quickshell` (which exports Quickshell's own `Window` = `QsWindow`, from the
`Quickshell._Window` module). When two modules export the same type name, QML
resolves `Window` to one of them — and with `import QtQuick` present, the bare
`Window { }` at line 14 resolves to **`QtQuick.Window` (a plain Qt window)**, *not*
Quickshell's `QsWindow`.

A plain `QtQuick.Window` created inside a `quickshell -p` process is **not tracked
or surfaced by Quickshell's Wayland/xdg-toplevel integration** under Hyprland — it
is not presented to the compositor as a managed toplevel, so it never maps (the
Hyprland window list shows no omaviz entry, while the compositor does list the
tester's Quickshell-managed window). Quickshell only presents windows it owns
(`QsWindow`/`PanelWindow`/`PopupWindow`), which register the proper xdg-toplevel
role and layer-shell/exclusion handling.

This is distinct from T-015 (ADR-0009, audio/bands): here the *window itself*
never appears, regardless of whether the engine produces frames.

## 3. Decision — the fix (spec for dev)

**Make the root `Window` resolve to Quickshell's `QsWindow`, not `QtQuick.Window`.**
Two equivalent ways; pick the cleaner:

- **(a) Drop the shadowing import:** remove `import QtQuick` (and ensure
  `import QtQuick.Controls` does not re-pull `QtQuick.Window`); then `Window`
  resolves unambiguously to Quickshell's `Window` (QsWindow). `Desktop.qml` uses
  only `Rectangle`/`Text`/`Button`/`Column`/`Loader`/`Timer`/`Connections`/`Binding`
  from QtQuick.Controls — none require the `QtQuick` base import's `Window`.
- **(b) Qualify explicitly:** keep imports but use `Quickshell.Window { }` (or
  alias) so the type is unambiguous.

Keep `visible: true` and `flags: Qt.Window | Qt.WindowStaysOnTopHint` (valid on
QsWindow). No change to the engine spawn, `VisualCanvasGL` binding, or audio path
(those are ADR-0009's scope).

**Verify during implementation:** confirm the launched window now appears in the
Hyprland window list (mapped, on the desktop layer) and renders the live
visualization. The fix is complete when `quickshell -p Desktop.qml`-style detach
produces a compositor-mapped, interactive window.

## 4. Consequences

- **Positive:** the detached desktop window actually maps and is visible on the
  desktop under Hyprland; resolves T-018 independently of T-015.
- **Positive (secondary):** using `QsWindow` also gives proper compositor
  integration (layer/exclusion, focus) for free, matching the shell's own config
  windows (`Bar.qml` etc. use `import Quickshell` + `Window`).
- **Negative / cost:** none meaningful; `QtQuick` import removal is local.
- **Test gate (tester, live shell — user GPU/UI approval):** detach → a real
  omaviz window appears in the Hyprland window list (mapped, visible), shows the
  live spectrum. Regression: must not regress the shell's own windows.

## 5. Rejected alternatives

- **Add `xwayland: 1` / force xdg-toplevel flags on the QtQuick.Window:** rejected
  — a bare Qt window inside Quickshell is simply not Quickshell-tracked; patching
  flags won't make Quickshell present it. The correct type is `QsWindow`.
- **Wrap the content in a `QsWindow` child of the QtQuick.Window:** rejected —
  nested toplevels are wrong; the root must *be* a QsWindow.
- **Assume it's the audio/bands bug (T-015):** rejected — the window never maps at
  all (no xdg-toplevel), so no frames could ever show regardless of engine output.

## 6. References
- `plugin/Desktop.qml` — imports (1-5), root `Window` (14), `visible`/`flags` (18-20).
- Quickshell `_Window` module (`/usr/lib/qt6/qml/Quickshell/_Window/qmldir`) —
  Quickshell's `Window` type (QsWindow).
- ADR-0009 (T-015) — audio/bands; separate from this window-mapping failure.
- APPLICATION_SPEC.md §7 (detach lifecycle), §13 (#23).
