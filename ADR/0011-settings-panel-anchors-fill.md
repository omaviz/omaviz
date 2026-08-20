# ADR-0011: Settings-panel `anchors.fill` on `KeyboardPanel` (T-019) — genuine QML error

| | |
|---|---|
| **Status** | Accepted (to implement in v7.6.x) |
| **Date** | 2026-08-19 |
| **Author** | architect (@architect) |
| **Task** | T-019 (roadmap #24) |
| **Applies to** | `plugin/Panel.qml` — `KeyboardPanel` surface (line 127) |
| **Supersedes** | none |
| **Superseded by** | none |

## 1. Context

`Panel.qml` builds the settings popup on the shared `qs.Ui/KeyboardPanel` surface.
The shell's `KeyboardPanel.qml` is a **`PanelWindow`** (Quickshell window type),
not a Qt `Item`:
```qml
// /usr/share/omarchy/shell/Ui/KeyboardPanel.qml:37
PanelWindow {
  id: root
  required property Item anchorItem
  required property QtObject bar
  ...
}
```
A `PanelWindow`/QsWindow is a top-level window (QWindow-derived). Unlike `Item`,
it **does not have an `anchors` attached property**.

## 2. Root cause (confirmed from the live log)

`Panel.qml:127` assigns:
```qml
KeyboardPanel {
  id: panel
  anchors.fill: parent      // <-- line 127: INVALID on a PanelWindow/QsWindow
  anchorItem: root.anchorItem || root.bar || root
  ...
}
```
`anchors` is not a property of a window, so QML raises:
`Panel.qml[127]: Cannot assign to non-existent property "fill"` and **aborts
construction of the `KeyboardPanel`** (and therefore the whole panel surface).
This is a genuine, separate QML error from T-014's module-resolution failure
(ADR-0008). It would bite *after* the module import is fixed, so both must be
resolved for the panel to surface.

`KeyboardPanel` internally sizes itself to the full screen via its own
`anchors { top/bottom/left/right: true }` (KeyboardPanel.qml:109-114), so the
intended `anchors.fill: parent` on the *outer* use-site was erroneous to begin
with — removing it changes nothing about the intended layout.

## 3. Decision — the fix (spec for dev)

**Remove the `anchors.fill: parent` line (Panel.qml:127).** No replacement is
needed: `KeyboardPanel`/`PanelWindow` fills its layer-shell surface on its own.
Keep the rest of the surface properties (`anchorItem`, `owner`, `bar`, `open`,
`centerOnBar: false`, `focusTarget`, `contentWidth/Height`, and the
`onAnchorItemChanged`/`onOwnerChanged` `forceLayout()` re-anchors from commit
85cde08).

This is a one-line deletion. It does not touch shaders, GPU, or the visual content.

## 4. Consequences

- **Positive:** eliminates the construction-aborting QML error; the panel surface
  can now instantiate once the module import (ADR-0008) is also resolved.
- **Negative / cost:** none.
- **Test gate (tester, live shell — user GPU/UI approval):** after this fix +
  ADR-0008, the panel must instantiate without a QML error; `quickshell` log shows
  no `Cannot assign to non-existent property "fill"` for Panel.qml.

## 5. Rejected alternatives

- **Replace with `width`/`height` or an `Item` wrapper:** rejected — unnecessary;
  `KeyboardPanel` already fills the layer-shell surface internally.
- **Leave it and suppress the warning:** rejected — the error *aborts
  construction*, not merely warns; suppression would hide a hard failure.

## 6. References
- `plugin/Panel.qml` — `anchors.fill: parent` (127), surface block (125-145).
- `/usr/share/omarchy/shell/Ui/KeyboardPanel.qml` — `PanelWindow` root (37),
  internal full-screen anchors (109-114); no `anchors` property on a window.
- ADR-0008 (T-014) — module resolution; this error is compounding/secondary.
- APPLICATION_SPEC.md §13 (#24).
