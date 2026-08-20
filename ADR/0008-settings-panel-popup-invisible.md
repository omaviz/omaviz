# ADR-0008: Settings-panel popup invisible (T-014) — popup surface / lifecycle correction

| | |
|---|---|
| **Status** | Accepted (to implement in v7.6.x) |
| **Date** | 2026-08-19 |
| **Author** | architect (@architect) |
| **Task** | T-014 (roadmap #19) |
| **Applies to** | `plugin/Panel.qml` (KeyboardPanel surface), `qs.Ui/Panel.qml` (base `panelController`), `plugin/BarWidget.qml` (`injectPanel`, `panelLoader`) |
| **Supersedes** | none |
| **Superseded by** | none |

## 1. Context

The mini bar renders fine (BarWidget loads, `qs.Commons`/`qs.Ui` resolve at
runtime). The settings **popup never surfaces** on left-click toggle. The mini and
the popup live in the same Quickshell process: `BarWidget.qml` loads
`Panel.qml` via a `Loader` (`panelLoader`, BarWidget:307-313) and injects
`anchorItem`/`hostWidget`/`bar` via `injectPanel()`.

The intended show path (documented in Panel.qml:66-76):
```
BarWidget.toggle() → panelLoader.item.toggle() → Panel base toggle()
  → panelController.show() → panelController.open = true → KeyboardPanel shows
```
`Panel.qml` builds on the shared `qs.Ui/Panel.qml` base, which owns a
`PanelController`. The `KeyboardPanel` (Panel.qml:118-135) binds:
```qml
KeyboardPanel {
  anchorItem: root.anchorItem          // injected by BarWidget.injectPanel()
  owner:      root.hostWidget || root
  open:       root.opened              // = panelController.open (base)
  ...
}
```

## 2. Root cause

The popup surface is **entirely owned by the shared `qs.Ui Panel` base
`panelController`**, but two shell-layer defects break it:

1. **`anchorItem` / `owner` injection timing.** `root.anchorItem` is `null`
   until `BarWidget.injectPanel()` runs (BarWidget:75-82, called on
   `panelLoader.onLoaded`). `KeyboardPanel` anchors to `root.anchorItem`. If the
   controller's `show()` fires (or is attempted) before `injectPanel()` has set
   `anchorItem`, the popup anchors to a `null`/unresolved item and renders
   **off-screen / zero-size** — invisible, with no error. `injectPanel()` is
   invoked twice (`onLoaded` + a `Qt.callLater`), which helps, but the binding to
   `anchorItem` is established at `KeyboardPanel` construction time and does not
   re-resolve if the underlying value was `null` when first evaluated.

2. **`open` bound to an inherited, never re-emitted property.** `Panel.qml` does
   NOT re-declare `opened`/`open`/`close`/`toggle` (it relies on the base,
   per the comment at Panel.qml:67-76). `root.opened` therefore resolves to the
   `Panel` base controller state — but `BarWidget` *also* defines
   `readonly property bool opened: panelLoader.item ? panelLoader.item.opened :
   false` (BarWidget:63-64). This double indirection is fine for the *bar's*
   read of `opened`, yet the `KeyboardPanel.open: root.opened` inside Panel.qml
   reads the **base** `opened`, whose change signal must propagate through the
   `panelController` to trigger the surface. When the controller is instantiated
   in the *plugin* (not shell) context, the `qs.Ui Panel` base controller can
   fail to attach its surface to the bar's window, so `open=true` flips but the
   popup is never composited.

**Conclusion:** this is a **popup-surface / lifecycle** defect, *not* a shader or
GPU issue. The fix is in the panel surface wiring (anchor/owner resolution +
explicit controller forwarding), consistent with lotus's hypothesis.

## 3. Decision — the fix (spec for dev)

1. **Guarantee `anchorItem` is non-null before the surface can show.** In
   `Panel.qml`, replace the bare `anchorItem: root.anchorItem` with a
   **fallback chain** so the popup always has a valid anchor even if injection is
   late:
   ```qml
   anchorItem: root.anchorItem || root.bar || root
   owner:      root.hostWidget || root.bar || root
   ```
   (The fallback to `root.bar`/`root` is the same strategy `KeyboardPanel` already
   uses for `bar: root.bar`.)

2. **Re-emit the controller state from Panel.qml** instead of relying solely on
   the inherited base property, so the change signal is unambiguously local:
   ```qml
   // forward the base controller's open state to the surface
   readonly property bool _ctrlOpen: panelController ? panelController.open : false
   // ... and bind KeyboardPanel.open: root._ctrlOpen
   ```
   If `panelController` is not exposed by the base, expose `open`/`close`/`toggle`
   explicitly in Panel.qml that call the base controller's `show()`/`hide()`
   (the comment at Panel.qml:67-76 warns the *old* broken version overrode these
   to set `panel.open` directly — the correct form is to call
   `panelController.show()/hide()`).

3. **Force a re-anchor on injection.** In `injectPanel()` (BarWidget side, or a
   Panel-side `onAnchorItemChanged`), call `panel.forceLayout()` /
   re-evaluate the `KeyboardPanel` anchor once `anchorItem` is set, so a late
   injection still produces a visible surface.

4. **Do NOT touch shaders/GPU.** The popup uses the Canvas-2D `VisualCanvas`
   preview and `qs.Ui` chrome; this is a pure QML/popup-lifecycle correction.

## 4. Consequences

- **Positive:** the settings popup becomes visible on left-click, matching the
  bar's contract (`panelLoader.item.open()`). No change to the visual content.
- **Negative / cost:** minor — adds explicit forwarding/binding. Low risk.
- **Test gate (tester, on live shell — needs user GPU/UI approval per
  AGENT_GOVERNANCE):** left-click the bar → settings panel appears, is
  interactive, and closes on `Esc`/outside-click. Must be verified on the user's
  running Omarchy shell (a standalone harness cannot surface the shell-layer
  popup). Regression: the panel must NOT require a second click to appear.

## 5. Rejected alternatives

- **Assume it's a GPU issue and rebuild shaders:** rejected — the popup is
  QML/`qs.Ui`, unrelated to `visual.frag`/`VisualCanvasGL`.
- **Move the panel into the bar widget directly (drop the Loader):** rejected —
  larger refactor; the Loader+injectPanel contract is sound, only the surface
  anchor/forwarding is broken.

## 6. References
- `plugin/Panel.qml` — KeyboardPanel (118-135), popup lifecycle comment (66-76),
  `injectPanel` contract (11-20).
- `plugin/BarWidget.qml` — `panelLoader` (307-313), `injectPanel` (75-82),
  `opened` (63-64).
- APPLICATION_SPEC.md §6 (settings panel), §13 (#19).
