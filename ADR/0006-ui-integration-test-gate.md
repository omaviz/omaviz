# ADR-0006: Mandatory UI integration test gate (closes "green gates, broken UI")

- **Status:** Accepted (process/governance amendment)
- **Date:** 2026-08-19
- **Lane:** architect (this ADR) → dev (impl + integration tests) → tester (live-shell QA) → reviewer (grade)
- **Referenced by:** `APPLICATION_SPEC.md` §9 (test strategy), §13 (roadmap #23)
- **Supersedes:** none · **Superseded by:** none
- **Companion ADRs (specific defects):** ADR-0008 (T-014/T-019), ADR-0009 (T-015), ADR-0010 (T-016)

## 1. Context

The user's diagnosis (verified by real evidence) is the binding constraint:

> "omaviz engine was working well I believe (test cases can prove it well) but
> the real testing should be on the UI. that's what the testing is totally
> lacking today."

This is correct and proven:
- **Engine logic is sound.** Suites green: cargo 34, model 55, glspectrum 18,
  barwidget 11. Live `omaviz-engine --source gen=mixed` emits non-silent,
  varied frames (max 0.3–0.74, never all-zero).
- **UI integration was never tested.** No suite launches the detached window,
  clicks the panel, or asserts the popup surfaces. The unit suites are green
  but **blind** to the shell — so T-014/T-015 shipped "passing" while broken in
  the running app.
- **The first "audit" was fake.** `run_audit.sh` emitted 9 identical frames
  (OMAVIZ_MODE never reached the harness). Retired. We will not fabricate
  captures.

### 1.1 Grounded root-cause (from source + the user's own observations)

The user reported: *"mini is visible and working"*, *"left click doesn't open
[settings], can't see the settings panel at all"*, *"right click does [open the
desktop]; desktop window (shows wave in the title) doesn't show anything and
doesn't respond to audio much."*

These are the highest-authority evidence and **contradict** two claims made in
the room:

- **"qs.Commons / qs.Ui are unresolvable and break the mini bar"** — FALSE per
  the user (mini works). `BarWidget.qml` imports `qs.Commons`/`qs.Ui`; if those
  failed in the shell the mini would not load. They resolve. The live-shell QML
  error `Panel.qml[120:13]: Cannot assign to non-existent property "fill"`
  **confirms** `qs.Ui` resolved (`KeyboardPanel` was accepted as a *type*; an
  unresolved type yields "X is not a type", not a property error). The
  settings-panel failure is a narrow code bug, not missing modules.
- **"T-018: detached window never maps a Wayland surface"** — FALSE per the user
  (they see the window with a "Wave" title). `hyprctl clients` not listing it is
  the **layer-shell measurement gap** (omarchy bar/desktop are layer-shell
  surfaces that `hyprctl clients`/`grim -g` cannot address — tester-confirmed).
  The window maps; it is **blank/unresponsive** (T-015). T-018 is reclassified
  as a measurement artifact (see §3).

## 2. Decision — unit suites are NOT sufficient for UI/integration changes

Amend the Definition of Done (AGENT_GOVERNANCE §5): for any UI/integration
change, dev MUST add integration tests exercising the shell paths, runnable
headlessly where possible and otherwise by tester on the live shell. RED-first
(governance §2): each test written to fail against current broken code, then
dev fixes minimally. Three required harnesses:

1. **Panel-popup visibility (T-014/T-019):** load `Panel.qml` (or a harness
   importing `qs.Ui`) and assert `opened` flips `true` on `root.toggle()` **and**
   that no QML error of the form `Cannot assign to non-existent property` is
   emitted during construction. Guards the `fill` regression directly.
2. **Detached-window bands flow (T-015):** a harness that launches `Desktop.qml`
   with `omaviz-engine --source gen=mixed`, asserts the engine child (a) spawns,
   (b) emits non-empty `bands` within N seconds, and (c) `VisualCanvasGL`'s
   `bands`/`density` bindings receive them. Uses `--source gen` so it does not
   depend on real audio capture.
3. **Click mapping (T-016):** assert `BarWidget.onPressed` maps
   `LeftButton → toggle()` (settings) and `RightButton → detach()` (desktop) —
   documents the contract and guards against an accidental swap.

Where headless Quickshell cannot render GL, tester runs them on the **live
shell** (requires the user's unlock + a layer-shell-aware capture method).

## 3. Reclassification (evidence-based)

- **T-018** ("detached window never maps") is **CLOSED as a measurement
  artifact** — the user sees the window; `hyprctl clients` is blind to
  layer-shell surfaces. The real defect is T-015 (content/audio).
- **T-014** root cause is the confirmed live QML error
  `Panel.qml:120: Cannot assign to non-existent property "fill"`
  (`KeyboardPanel`) — see ADR-0008. Not a missing-module issue.
- **T-015** leading hypothesis is the 2nd-engine PipeWire node-name collision —
  see ADR-0009; verify on the live shell.
- **T-016** is a user UX decision — see ADR-0010; no code change without the
  user's explicit call.

## 4. Consequences

**Positive:** closes the exact gap the user identified — UI integration becomes a
hard gate, not a blind spot. **Negative / gaps:** needs a runnable integration
path (live shell + layer-shell capture); visual sign-off remains impossible
until then — we will not fake it.
