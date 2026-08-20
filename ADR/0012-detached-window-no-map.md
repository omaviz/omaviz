# ADR-0012: Detached desktop window never maps (T-018) — INVESTIGATION (root cause UNCONFIRMED)

| | |
|---|---|
| **Status** | **BLOCKED — root cause unconfirmed; original theory RETRACTED; controlled investigation required on user's live system** |
| **Date** | 2026-08-19 (theory retracted + empirical re-investigation this revision) |
| **Author** | architect (@architect) |
| **Task** | T-018 (roadmap #23) |
| **Applies to** | `plugin/Desktop.qml` — root `Window` (lines 1, 14), `BarWidget.detach()` launch path |
| **Supersedes** | earlier ADR-0012 draft asserting "import QtQuick shadows Quickshell Window" — **RETRACTED as incorrect** |
| **Superseded by** | none |

## 0. RETRACTION (important)

The prior ADR-0012 claimed the root cause was: *"`Desktop.qml` imports `import
QtQuick`, which shadows Quickshell's `Window`, so the root resolves to
`QtQuick.Window` (a bare, untracked window) instead of `QsWindow`, and Hyprland
never surfaces it."* **This is wrong, and must not be used by dev.** Two independent
corrections:

1. `QtQuick` does **not** export a `Window` type (that lives in `QtQuick.Window`).
   So `import QtQuick` cannot shadow Quickshell's `Window`. The omarchy shell's own
   `shell.qml` imports BOTH `QtQuick` and `Quickshell` and works (verified by lotus).
2. Empirical test (below) shows the root `Window` **does** surface under Hyprland in
   every configuration tried — so the "never maps" symptom is NOT a structural
   window-type defect.

The original theory is withdrawn. dev must NOT build on it.

## 1. Context

Production log (reported by lotus): pid 9927 (`Desktop.qml`, launched via the
omarchy shell's `BarWidget.detach()`) + its engine pid 9948 ran, but Hyprland's
window list showed **no mapped omaviz window** (the tester's own harness
`TestDesktop.qml` mapped at pid 80790). Separately, T-015 (ADR-0009) reports the
mapped window is *blank/no-audio* — those are distinct; T-018 is specifically about
the window **not appearing at all** in the user's environment.

## 2. Empirical re-investigation (architect, this session)

I reproduced the launch on the user's machine (Hyprland 0.56.2, Quickshell 0.3.0,
`WAYLAND_DISPLAY=wayland-1`) and checked `hyprctl clients` each time:

| # | Launch form | Result |
|---|-------------|--------|
| 1 | Bare `Window { visible:true }` via `quickshell -p /tmp/qs_test_bare/Window.qml` | **Mapped** (`org.quickshell`, mapped=True) |
| 2 | Real `plugin/Desktop.qml` via `quickshell -p .../Desktop.qml` | **Mapped** (pid 118393, mapped=True) |
| 3 | `Desktop.qml` launched as a `Process` *child of an already-running Quickshell* (mimics `BarWidget.detach()`) | **Mapped** (pid 121088, mapped=True) |

**Conclusion:** In this environment the detached window surfaces correctly in all
forms, including the exact `quickshell -p Desktop.qml` production command and the
child-of-shell `Process` form. Therefore the "never maps" failure is **NOT a
deterministic structural window-type defect** and cannot be fixed from source
inspection alone. It is environment/state-dependent and only reproduced in the
user's live log.

## 3. What is NOT the cause (ruled out)

- ~~`import QtQuick` shadowing Quickshell `Window`~~ — false (see §0).
- ~~Bare `QtQuick.Window` untracked by Quickshell~~ — false; a Quickshell `Window`
  is what's used and it surfaces.
- ~~Standalone `quickshell -p` lacking window surfacing/attach that the shell
  provides via `qs.Commons`/`qs.Ui`~~ — false; a standalone bare `Window` maps
  without any `qs.*` modules.
- Layer-shell attachment — false here; `Desktop.qml` uses a plain toplevel
  `Window`, which maps fine.

## 4. Most likely remaining hypotheses (NOT confirmed — need live evidence)

Given the symptom only appears in the user's environment, the cause is likely one
of:

- **(H1) Launch-context env difference.** The production `Desktop.qml` is spawned
  by `BarWidget.detach()` (`quickshell -p <pluginDir>/Desktop.qml`) from *within*
  the running omarchy shell. The shell's Quickshell process may pass an environment
  (or `QML2_IMPORT_PATH` / `QT_QPA_PLATFORM` / Wayland socket) under which the
  child's window fails to present, while a clean standalone launch works. The
  `BarWidget.qml` comment (lines 138-145) explicitly warns that setting
  `detachProc.environment` would *wipe* `PATH`/`WAYLAND_DISPLAY`/`HOME`; the child
  currently inherits the parent env, which is correct, but some env var the shell
  sets may still interfere with window presentation.
- **(H2) A transient/post-load error closes the window before it composites.** The
  real `Desktop.qml` log (run this session) shows a clean "Configuration Loaded"
  with no QML error — but the production failure may involve a later runtime error
  (e.g. `VisualCanvasGL`/`visual.qsb` load failure, or a binding error in
  `pushSettings()`) that destroys the surface. Note: the tester's harness uses a
  different renderer-loading path (`Loader` + `onItemChanged: apply()`) than
  `Desktop.qml` (`Connections`-driven `pushSettings()`); a difference there could
  explain why the harness maps but production does not.
- **(H3) Workspace/monitor/visibility race.** `visible: true` is set, but if the
  production launch happens while the shell is mid-(re)start or the compositor is
  busy, the toplevel may be created unmapped and never shown. Less likely given a
  clean log.

## 5. Required next step BEFORE any code change (no source edits yet)

The root cause is **not determinable from source in this environment** because the
failure does not reproduce here. Dev/tester must reproduce on the **user's live
system** (where it did occur) and capture:

1. `hyprctl clients` immediately after clicking Detach — does an `org.quickshell`
   entry appear at all, and if so is `mapped` 0 or 1?
2. The `quickshell -p Desktop.qml` runtime log
   (`/run/user/1000/quickshell/by-id/*/log.qslog`) from the **production** launch —
   any `Error:`/`Cannot assign`/`Exception` line, especially after
   "Configuration Loaded".
3. `WAYLAND_DISPLAY` / `QT_QPA_PLATFORM` / `QML2_IMPORT_PATH` seen by the child
   process (compare a working standalone launch vs the in-shell launch).
4. Whether the engine (pid 9948) actually produced frames (T-015 angle) — to
   separate "window never maps" from "window maps but blank".

Only after (1)-(4) from the live repro should a specific fix be specified. **Do NOT
let dev implement any window-type change yet** — the original theory is retracted
and the symptom is unconfirmed here.

## 6. Spec for dev (CONDIAL — only after live repro pinpoints cause)

Pending repro, the *safest* hardening (low-risk, does not assume a false cause) is
to **make `Desktop.qml`'s renderer-loading path match the harness that is known to
map**: replace the `Connections`-driven `pushSettings()` (fired on
`onConfigChanged`/`onItemChanged`) with the harness pattern — `Loader` +
`onItemChanged: apply()` + per-frame `Binding` for `bands`/`silent` — and add an
`onCompleted`/`onItemChanged` guard so the surface is never left in a half-bound
state. This is also a T-015 (ADR-0009) hardening. **But this is contingent on the
live repro confirming H2**; it is NOT a fix for a confirmed T-018 cause yet.

## 7. Consequences

- **Positive:** the false shadowing theory is withdrawn, preventing wasted dev work
  on a non-defect. The investigation is now evidence-driven.
- **Negative / cost:** T-018 stays BLOCKED until the user's live repro is captured;
  cannot ship a code fix from this environment.
- **Test gate (tester, on user's live shell — needs user GPU/UI approval per
  AGENT_GOVERNANCE):** reproduce Detach on the user's machine, capture the four
  artifacts in §5, and report which hypothesis holds. Only then does dev proceed.

## 8. Rejected alternatives

- **Implement the retracted shadowing fix (drop `import QtQuick`):** rejected —
  theory is false; removing `import QtQuick` would also break `Rectangle`/`Text`/
  `Button`/`Column` usage and not fix anything.
- **Wrap `Desktop.qml` root in `ShellRoot`:** rejected — a bare `Window` already
  maps (test 1), and `ShellRoot` is for multi-window shell hosts, not required for
  a single standalone window.
- **Switch to `PanelWindow`/layer-shell:** rejected — the window is a normal
  desktop toplevel by design; layer-shell is for bar-anchored popups (KeyboardPanel),
  and a plain `Window` surfaces fine.

## 9. References
- `plugin/Desktop.qml` — imports (1-5), root `Window` (14), `visible`/`flags` (18-20),
  `pushSettings()` (101-117), `Connections`-driven apply (88-96).
- `plugin/BarWidget.qml` — `detach()` (161-179), env warning (138-145).
- `plugin/tests/integration/TestDesktop.qml` — harness that mapped (pid 80790);
  uses `Loader`+`onItemChanged:apply()`+`Binding`, differs from `Desktop.qml`.
- Empirical test logs this session: bare `Window` mapped; real `Desktop.qml` mapped
  (pid 118393); child-of-shell `Desktop.qml` mapped (pid 121088).
- APPLICATION_SPEC.md §7 (detach lifecycle), §13 (#23).
