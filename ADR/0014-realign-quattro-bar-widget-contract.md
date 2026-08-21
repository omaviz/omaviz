# ADR-0014: Realign plugin to omarchy Quattro `bar-widget` contract (T-028)

- **Status:** Accepted (spec for T-028)
- **Date:** 2026-08-20
- **Lane:** architect (this ADR) → dev (impl) → tester (verify via `grim -o eDP-1` that the bar shows the live spectrum) → reviewer (grade)
- **Referenced by:** `APPLICATION_SPEC.md` §13 (roadmap #29)
- **Evidence base:** `omarchyplugins.com/develop.html` (canonical dev guide) + `github.com/basecamp/omarchy/tree/quattro/shell/plugins` README (first-party plugin catalogue). User supplied these references; this ADR realigns the plugin to them.

## 1. Context

The user reported the bar visualizer shows **nothing** even though the engine runs and the shell lists the plugin as enabled. Comparing `plugin/` against the omarchy contract the user linked shows two structural deviations that are the root cause — not a load failure:

1. **`WidgetButton` has empty text and a near-zero width**, so the spectrum it paints is invisible. The canonical clock (`develop.html` §03) sizes its button via `text` (`implicitWidth: button.implicitWidth`); our `BarWidget.qml:168` sets `text: ""` and `implicitWidth: Style.space(2) + root.barCount * (root.slotW + Style.space(2))` where `root.slotW = 3` (a ~9px sliver). The bars render inside that sliver → not visible in the bar. This is the primary reason "the bar is empty."
2. **`Panel.qml` loads `KeyboardPanel` directly** (a `PanelWindow` that opens its own layer-shell surface) instead of using the spec's **`Panel` base** (Quattro's `qs.Ui Panel`) which owns the `PanelController` show/hide lifecycle and keeps the popup inside the bar process. `develop.html` §03 is explicit: *"Quattro's `Panel` base provides the open state and controller; `KeyboardPanel` anchors the surface to the bar button... Escape closes it through `PanelKeyCatcher`."* Our standalone `KeyboardPanel` violates that pattern and is the reason the panel never surfaced (the `fill`/construct errors in T-019/T-022 were symptoms of bypassing the base).

The plugin also still carries **detach machinery the user explicitly rejected**: `Panel.qml:461-465` still renders a Detach button; `toggleDetach()` references `hostWidget.detach`, which dev removed in `e0ec2a4`. So the button is dead and the feature is contra the user's standing instruction ("no right-click / no desktop window") and the spec's "never start a second Quickshell process."

## 2. Decision — mandatory realignment to the Quattro contract

### 2.1 Bar widget
- **CRITICAL (verified against `/usr/share/omarchy/shell/Ui/WidgetButton.qml`):**
  `WidgetButton` computes `hasVisualContent: text !== ""` as a **read-only
  property** and derives both `opacity` and `implicitWidth` from it:
  ```
  property bool hasVisualContent: text !== ""          // base, not overridable
  visible: hasVisualContent || keepSpace
  opacity: !hasVisualContent || concealed ? 0 : (dimmed ? 0.45 : 1)
  implicitWidth: fixedWidth > 0 ? fixedWidth
                 : (vertical ? barSize : Math.max(12, label.implicitWidth + scaledHorizontalMargin*2))
  ```
  So setting `text: ""` (even with `hasVisualContent: true` in our file) makes
  the base recompute `hasVisualContent=false` → **opacity 0 + width collapses to
  ~29px** (label width 0). The nested `Item`/Repeater children DO paint, but the
  parent button is invisible and 29px wide, so the spectrum is not seen. **This
  is the real reason the bar was empty** (confirmed by the live `4e07a74`
  `BarWidget.qml` which still has `text:""` — dev's "width fix verified" was
  false; he widened `implicitWidth` but opacity stayed 0).
- **Required fix (any one):** (a) `text: " "` (non-empty) so `hasVisualContent`
  is true and the button is opaque with a real label width; **or** (b) set
  `fixedWidth: <px>` (e.g. `Style.space(2) + barCount*(slot+gap)`) which forces
  `implicitWidth` regardless of text; **or** (c) render the spectrum as the
  label string itself (unicode blocks ▁▂▃▄▅▆▇█ rebuilt per frame from
  `root.spectrumBands`, like a ticker) — this also satisfies `text !== ""`.
  ADR-0014 originally prescribed (a)/(b); lotus's (c) is equally valid. All
  three require `text` non-empty OR `fixedWidth` set — that is the gating fact.
- Keep the only interaction as **left-click → `root.toggle()`** (settings
  panel). No right-click (per user; matches ADR-0010 / T-016 decision).

### 2.2 Panel (settings popup)
- Realign `Panel.qml` to the spec's structure (modeled on `develop.html` §03):
  - Root type is **`Panel`** (from `qs.Ui`), not `KeyboardPanel`.
  - The `Panel` base owns `opened`/`open()`/`close()`/`toggle()` via `PanelController`; `BarWidget.injectPanel()` forwards `bar`/`anchorItem`/`hostWidget`/`settings` to it (already done).
  - The popup surface is `KeyboardPanel` placed **inside** the `Panel` base (anchored to `anchorItem`), with `open: root.opened`, `owner: root.hostWidget`, `bar: root.bar`, and a `PanelKeyCatcher` for Escape. This is the exact pattern the spec documents.
- Remove the standalone-`KeyboardPanel`-as-root approach (the source of T-019/T-022 construct errors).

### 2.3 Remove detach remains
- Delete `Panel.qml:451-466` Detach button + footer row, and `toggleDetach()` (`:108-113`). The detached desktop window was already removed from `BarWidget`; the panel must not advertise a feature that does not exist.
- Remove any residual `desktop.active`/`detach` references in the panel config logic (they now drive a non-existent behavior).

### 2.4 Manifest
- **No change required.** `kinds:["bar-widget"]` + `entryPoints.barWidget:"BarWidget.qml"`, `defaultSection:"right"` already match the clock example in `develop.html`. The violations were runtime/layout, not manifest.

## 3. Consequences
- **Positive:** the bar spectrum becomes visible (real button width) and the settings panel opens through the supported `Panel`/`PanelController` lifecycle (no construct errors). Matches the omarchy contract, so future `omarchy plugin validate` + `qmllint` pass cleanly and the plugin is supportable.
- **Negative / cost:** dev must restructure `Panel.qml` (wrap `KeyboardPanel` in `Panel` base) and fix the button width. The earlier T-019/T-022 fixes were partial because they patched the standalone-`KeyboardPanel` path; this ADR replaces that path.
- **Test gate (tester):** after fix, `grim -o eDP-1` (with display awake) must show the omaviz spectrum in the bar; one left-click must open the settings panel (capture the panel-open frame). The existing `barwidget` test asserts the click contract — extend it to assert `WidgetButton.text` is non-empty / `implicitWidth > 0`.

## 4. Rejected alternatives
- **Keep standalone `KeyboardPanel` and just paper over the `fill` error (T-019):** rejected — it bypasses the supported popup lifecycle, which is why the panel never opened; the spec mandates the `Panel` base.
- **Leave `text:""` and force width via a fixed `implicitWidth`:** insufficient — a fixed ~9px sliver (`root.slotW*3`) still hides the spectrum. Width must track the real per-bar pixel budget.
- **Re-add the detach desktop window:** rejected — explicitly contra the user's instruction and the spec's "no second Quickshell" rule.

## 5. References
- `omarchyplugins.com/develop.html` §02 (manifest), §03 (BarWidget/Panel structure, `Panel` base + `KeyboardPanel`), §06 (validation; "plugin validates but not listed → rescanPlugins").
- `github.com/basecamp/omarchy/tree/quattro/shell/plugins` README: first-party `bar-widget` catalogue; "never start a second Quickshell process" rule; `Panel`/`KeyboardPanel` contract.
- `plugin/BarWidget.qml:163-168` (`text:""`, `implicitWidth` with `slotW=3`); `:178-180` (left-click only).
- `plugin/Panel.qml:33` (root is `Panel` type — already `Panel`, but `:131` loads `KeyboardPanel` directly without the spec's wrap), `:451-466` (Detach button).
- `plugin/manifest.json` — no change needed (already matches clock example).
