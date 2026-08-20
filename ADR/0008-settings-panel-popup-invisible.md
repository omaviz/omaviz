# ADR-0008: Settings-panel popup invisible (T-014) — module resolution (CONFIRMED root cause)

| | |
|---|---|
| **Status** | Accepted (to implement in v7.6.x) |
| **Date** | 2026-08-19 (root cause re-confirmed this revision) |
| **Author** | architect (@architect) |
| **Task** | T-014 (roadmap #20) |
| **Applies to** | `plugin/Panel.qml` (imports `qs.Commons`/`qs.Ui`), `plugin/BarWidget.qml`, plugin packaging / QML import path, `qs.Ui`/`qs.Commons` provision |
| **Supersedes** | earlier ADR-0008 draft that (incorrectly, per retracted T-017) denied the missing-module cause |
| **Superseded by** | none |

## 1. Context

`plugin/Panel.qml` (and `BarWidget.qml`) begin with:
```qml
import qs.Commons
import qs.Ui
```
`qs.Commons` and `qs.Ui` are QML *modules* registered by the omarchy shell via
`/usr/share/omarchy/shell/Commons/qmldir` (`module qs.Commons`) and
`/usr/share/omarchy/shell/Ui/qmldir` (`module qs.Ui`). For Quickshell to resolve
`import qs.Commons`/`import qs.Ui`, those module directories must be on the QML
import path of the *plugin's* QML engine.

## 2. Root cause — CONFIRMED (re-corrected this revision)

An earlier draft of this ADR (based on the retracted T-017 tester report) claimed
the mini loading proved `qs.*` resolves and that the cause was instead an
`anchors.fill` error. That was **wrong**. lotus grep'd **all 31 live quickshell
logs**: the `qs.Commons`/`qs.Ui` **"unresolvable import" warning appears in BOTH
standalone launches (rn794o1kt) AND shell-driven launches (oc7s3o1kt, pi754o1kt,
z27d3o1kt, byyxn1kt, …).** Therefore:

> **The plugin's QML engine does NOT have `/usr/share/omarchy/shell` on its
> import path in either launch context, so `import qs.Commons` / `import qs.Ui`
> fails, Panel.qml fails to instantiate, and the settings popup never surfaces.**

This is the **primary, confirmed** root cause of T-014. The mini bar works only
because `BarWidget.qml` itself is loaded *by the shell* and the shell's own
components happen to resolve — but the *plugin's* resolution of `qs.*` does not
propagate to the standalone/child engine context. (Note: Desktop.qml deliberately
avoids `qs.*`, which is why the detached window launches at all — see ADR-0009/
ADR-0012 — but the settings panel cannot avoid `qs.Ui` because it builds on
`qs.Ui/Panel.qml` + `KeyboardPanel`.)

## 3. Decision — how `qs.Commons`/`qs.Ui` are provided to the plugin

**RECOMMENDATION: vendor the minimal required subset of `qs.Commons` and `qs.Ui`
into the plugin** so `import qs.Commons`/`import qs.Ui` resolve from the plugin's
*own* import path, independent of how the shell configures its engine.

Rationale:
- Matches the project's Architecture A (single-package, drop-in, no system
  dependency) and the existing self-contained philosophy already applied to
  `Desktop.qml` ("avoids shell-only modules").
- Fixes the failure in **both** contexts (standalone `quickshell -p` and
  shell-driven), because the modules travel *with* the plugin.
- Removes the silent dependency on shell import-path configuration, which the
  logs prove is not reliably provided.

**What to vendor (minimal subset actually used by the plugin):**
- `qs.Commons`: `Border.qml`, `Color.qml`, `Style.qml`, `Util.qml` (all
  singletons, per `Commons/qmldir`) + a local `qmldir` with `module qs.Commons`.
- `qs.Ui` (only the types Panel.qml/BarWidget.qml reference): `Panel.qml`,
  `PanelController.qml`, `KeyboardPanel.qml`, `PanelKeyCatcher.qml`,
  `PanelSectionHeader.qml`, `PanelSeparator.qml`, `ButtonGroup.qml`, `Button.qml`,
  `ToggleSwitch.qml` (and any transitive deps those pull in, e.g. `BorderSurface`,
  `PopupCard` only if used) + a local `qmldir` with `module qs.Ui`.
- Lay them out under `plugin/qs/Commons/` and `plugin/qs/Ui/` so QML resolves
  `qs/Commons/qmldir` and `qs/Ui/qmldir` relative to the plugin directory.

**Sync / drift control (required):** the vendored copy is a *pinned snapshot*. Add
a release step (script or CI check) that copies the modules from
`/usr/share/omarchy/shell` at plugin tag time and fails CI if the plugin's local
copy diverges from the shell's API surface it depends on. Document the dependency
explicitly so a future shell API change is caught.

**Rejected alternative — shell bridges the import path:** have the omarchy shell
pass its `QML2_IMPORT_PATH` / import-path list to the plugin's Quickshell engine.
Rejected as primary because (a) it still fails for the standalone
`quickshell -p Desktop.qml`-style launch where no shell is present to bridge, and
(b) it depends on shell cooperation outside the plugin's control, whereas the
plugin's single-package contract says it must be self-sufficient. Acceptable only
as a *temporary* mitigation while vendoring lands.

## 4. Secondary / compounding fixes (kept, necessary-but-insufficient)

dev's anchor fix (commit **85cde08**) added a fallback anchor chain
(`anchorItem: root.anchorItem || root.bar || root`) and `forceLayout()` re-anchor
on injection. **This is necessary but NOT sufficient** — it only helps once the
QML actually loads, which it cannot until §3 (module provision) is done. Keep it.
Additionally, a *separate* genuine QML error in the same file must be removed —
see **ADR-0011 (T-019)**: `KeyboardPanel` is a `PanelWindow`/Quickshell window and
has no `anchors` property, yet Panel.qml:127 assigns `anchors.fill: parent`, which
raises `Cannot assign to non-existent property "fill"` and aborts construction.
Both §3 and ADR-0011 must land for the panel to surface.

## 5. Consequences

- **Positive:** settings popup loads and surfaces in both standalone and
  shell-driven launches; removes the silent module dependency.
- **Negative / cost:** vendored modules must be kept in sync with the shell
  (mitigated by the CI/sync step in §3). Some duplication of shell QML.
- **Test gate (tester, live shell — needs user GPU/UI approval per
  AGENT_GOVERNANCE):** left-click bar → settings panel appears, interactive,
  closes on Esc/outside-click. Regression: must not require a second click; must
  work whether launched standalone or by the shell.

## 6. Rejected alternatives

- **Assume the panel is a GPU/shader issue:** rejected — purely a QML import /
  module-resolution failure.
- **Rely on shell import-path bridging alone:** rejected (see §3).
- **Just delete the `qs.*` imports from Panel.qml:** rejected — the panel is built
  on `qs.Ui/Panel.qml` + `KeyboardPanel`; those types cannot be removed without
  rewriting the entire surface.

## 7. References
- `plugin/Panel.qml` — `import qs.Commons`/`qs.Ui` (5-6), `KeyboardPanel` surface
  (125-145), `anchors.fill` (127, see ADR-0011).
- `plugin/BarWidget.qml` — `import qs.Commons`/`qs.Ui` (4-5), `injectPanel` (75-82).
- `/usr/share/omarchy/shell/Commons/qmldir` (`module qs.Commons`, 4 singletons),
  `/usr/share/omarchy/shell/Ui/qmldir` (`module qs.Ui`, Panel/KeyboardPanel/…).
- `plugin/Desktop.qml` — deliberately avoids `qs.*` (comment line 9).
- APPLICATION_SPEC.md §2 (Architecture A), §6 (settings panel), §13 (#20).
