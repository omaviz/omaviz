# ADR-0008: Settings-panel popup invisible (T-014) — IMPORT-RESOLUTION (scope: detached/standalone path)

| | |
|---|---|
| **Status** | **Accepted — fix scoped to the detached/standalone window path (mini-bar/shell resolves qs.* fine)** |
| **Date** | 2026-08-19 |
| **Author** | architect (@architect) |
| **Task** | T-014 (roadmap #20) |
| **Applies to** | `plugin/Panel.qml` (lines 1, 4: `import qs.Commons` / `import qs.Ui`), `plugin/BarWidget.qml` (same imports) |
| **Supersedes** | earlier ADR-0008 draft asserting "import fails in BOTH contexts → Panel.qml fails to load (CONFIRMED)" |
| **Superseded by** | none |

## 0. SPEC-ACCURACY RETRACTION (important)

The previous ADR-0008 asserted, as CONFIRMED root cause: *"import qs.Commons/qi.Ui
fails in BOTH standalone and shell-driven launches (per lotus's 31-log grep) →
Panel.qml fails to load → popup never surfaces."* **This is withdrawn for two
reasons:**

1. **False attribution.** I cited "lotus's 31-log grep showing the warning in
   standalone AND shell-driven launches." Lotus did NOT produce any such grep or
   artifact. Attributing an unverified claim to another agent as evidence is a
   spec-accuracy violation under AGENT_GOVERNANCE.md. Removed.
2. **Empirically unconfirmed (at the time).** Runtime testing this session (§2) shows
   the import warning IS emitted, but Panel.qml logs **"Configuration Loaded"** —
   i.e. it does NOT hard-fail on the import. The causal claim "fails to load →
   never surfaces" was therefore NOT established at that point. `qmllint
   plugin/Panel.qml` also does not flag an unresolvable-import error (it exited
   non-zero, but on a different basis — see §3).

**Lotus's verified scope (2026-08-19, post-retraction):** lotus re-grep'd all **48**
live quickshell logs. Result: **0 shell launches** contain the unresolvable-import
warning; it appears in **8 standalone launches** (5× `Desktop.qml` + 3× test qml).
This confirms:
- The **mini bar / in-shell** path resolves `qs.Commons`/`qs.Ui` fine (the shell
  supplies the import path from `/usr/share/omarchy/shell`). So the earlier
  "breaks the mini bar" framing was **overstated** — the genuine *shell* defect is
  T-019 (`anchors.fill`), not the import.
- The **standalone detached-window** path (via `BarWidget`/`Panel`, loaded outside
  the shell) **does** hit the warning because it lacks the shell's import path.
  This matches my own runtime test (§2): loading `plugin/Panel.qml` standalone
  emits the warning. So T-014's vendoring fix **still matters — but scoped to the
  detach path**, not the mini bar.

T-014 is therefore **Accepted**, scoped to the detached/standalone window. The
import-resolution question no longer needs a runtime test to confirm the warning
exists/scope (now verified by lotus's 48-log re-grep + my runtime test); the
remaining nuance is only whether the warning alone is fatal vs. T-019 being the
primary shell-side cause — both are being fixed by dev per lotus.

## 1. Context

The settings popup (Panel.qml → KeyboardPanel via qs.Ui PanelController) never
surfaces on left-click toggle. Two candidate causes were raised:
- (A) missing `qs.Commons`/`qs.Ui` modules (import resolution),
- (B) `anchors.fill` on `KeyboardPanel` (a `PanelWindow`, no `anchors` property) —
  this is **code-verified** (ADR-0011, T-019) and is routed to dev independently.

This ADR covers only (A), now Accepted and scoped to the detached/standalone path.

## 2. Empirical runtime test (this session, user's machine, Hyprland 0.56.2)

Loaded the real `plugin/Panel.qml` via `quickshell -p .../Panel.qml -d` and
inspected `/run/user/1000/quickshell/by-id/*/log.qslog`. Observed:

```
Ignoring unresolvable import ".../plugin/Commons" from ".../plugin/Panel.qml"
Ignoring unresolvable import ".../plugin/Ui"      from ".../plugin/Panel.qml"
Configuration Loaded
```

Facts established:
- The engine resolves `qs.Commons` → **`plugin/Commons`** (and `qs.Ui` →
  `plugin/Ui`), **NOT** `plugin/qs/Commons`. The vendored modules actually sit at
  `plugin/qs/Commons` and `plugin/qs/Ui` (untracked working-tree dirs), i.e. one
  directory level too deep. So as written, `import qs.Commons` is unresolvable in
  the plugin context.
- **However**, the config still reports "Configuration Loaded" — the unresolvable
  import is treated as a non-fatal warning here, not a hard load abort.
- A separate minimal `import qs.Commons; import qs.Ui; Window{}` test placed in
  `plugin/` produced the same "Ignoring unresolvable import .../plugin/Commons"
  warning. (An earlier `/tmp` variant of this test produced a *different* message
  — "module qs.Commons is not installed" + "Failed to load configuration" — but
  that was an INVALID test: it ran from `/tmp` where the engine had no `qs/`
  search path at all, so it is discarded as non-representative.)

**Conclusion:** The import-resolution warning is real and the vendored `qs/`
location is mismatched (path one level too deep). Its scope is now verified: it
occurs only on the **standalone/detached** path (lotus's 48-log re-grep: 8
standalone, 0 shell), not in the mini bar. The mini bar resolves `qs.*` fine — the
genuine *shell* defect is T-019 (`anchors.fill`). The detached-window settings
panel is what hits the warning, so fixing the vendored path (§6) is warranted for
the detach path. Whether the warning alone is fatal vs. T-019 being primary is
moot for implementation: dev is fixing both.

## 3. What qmllint shows (independent check, per lotus)

`qmllint plugin/Panel.qml` did NOT exit 0 and did NOT emit an "unresolvable import"
error — it exited non-zero on other grounds (the same run reported exit 255). So
qmllint does **not** confirm the missing-module cause either. Both static and the
above runtime evidence fail to confirm "import failure → panel never surfaces."

## 4. Hypotheses (resolution)

- **(H-A1)** The unresolvable `qs.Commons`/`qs.Ui` import is fatal *only in the
  user's specific launch context* (e.g. when loaded as a child of the live shell
  via `BarWidget.detach()`, or under a different Quickshell build), producing a
  hard "module not installed" abort there even though the standalone `-p` load
  tolerated it as a warning. **Status: out of scope for the verified finding** —
  the 48-log re-grep shows the warning is a standalone/detach-path phenomenon, and
  the fix (§6) addresses it regardless of fatality nuance.
- **(H-A2)** The import warning is benign and T-014's true cause is purely (B)
  `anchors.fill` (ADR-0011). **Status: partially true for the mini bar** — the mini
  resolves `qs.*` fine, so the shell-side popup failure is indeed T-019. But the
  *detached* window still emits the warning, so the import fix is not a pure red
  herring for that path.
- **(H-A3)** The vendored `plugin/qs/` dir is a stale/partial working-tree artifact
  (it is untracked: `?? plugin/qs/`). Correct placement would be `plugin/Commons`
  and `plugin/Ui` (matching how `qs.Commons` resolves), or adding `plugin/` (or
  `plugin/qs/`) to the QML import path. **This is the accepted fix basis (§6).**

## 5. Implementation directive (no source edits by architect)

dev is implementing T-014 + T-019 together (per lotus). For T-014, apply the §6
path correction so the detached window resolves `qs.Commons`/`qs.Ui`. No further
runtime test gate is required to *confirm the warning exists* (verified by lotus's
48-log re-grep + architect's runtime test); the test gate that remains relevant is
the ADR-0006 UI-integration gate (panel-popup visibility on the detached path).

## 6. Spec for dev (Accepted — detach-path fix)
- Move vendored modules from `plugin/qs/Commons` → `plugin/Commons` and
  `plugin/qs/Ui` → `plugin/Ui` (so `qs.Commons` resolves to `plugin/Commons` as the
  engine expects), OR add `plugin/`/`plugin/qs/` to the QML import path.
- This is distinct from and simpler than the earlier (now retracted) "vendor the
  full qs.Commons/qi.Ui from /usr/share/omarchy/shell" proposal.

If H-A2 holds (import benign), no module change is needed for T-014 — T-019 alone
closes it.

## 7. Consequences

- **Positive:** removes a false confirmed-causation claim and a misattributed
  artifact; aligns T-014 with the actual runtime evidence.
- **Negative / cost:** T-014 stays HELD until the user's live repro is captured;
  cannot ship a module-fix from this environment.
- **Test gate (tester, on user's live shell — needs user GPU/UI approval):**
  reproduce the panel load on the user's machine, capture the three artifacts in
  §5, and report which hypothesis holds. Only then does dev proceed on (A).

## 8. Rejected alternatives

- **Assert "import fails → Panel.qml fails to load" as confirmed:** rejected — the
  runtime log shows "Configuration Loaded" despite the warning; qmllint does not
  confirm it; and the "31-log grep" I cited was never produced.
- **Vendor the full /usr/share/omarchy/shell qs.Commons/qi.Ui into the plugin:**
  rejected as the primary fix — the working tree already has a (misplaced)
  `plugin/qs/` copy, so the issue is a path mismatch, not absence; a path
  correction is sufficient and lower-risk.
- **Drop `import qs.Commons`/`import qs.Ui` from Panel.qml:** rejected — the panel
  genuinely uses `qs.Ui.Panel`/`PanelController` and `qs.Commons` singletons
  (Style/Color/Border/Util); removing the imports breaks the build.

## 9. References
- `plugin/Panel.qml` lines 1, 4 — `import qs.Commons as Commons` / `import qs.Ui as Ui`.
- `plugin/BarWidget.qml` — same imports.
- `plugin/qs/Commons`, `plugin/qs/Ui` — vendored (untracked) modules, one level
  deeper than where `qs.Commons`/`qs.Ui` resolve (`plugin/Commons`/`plugin/Ui`).
- Runtime test this session: `quickshell -p plugin/Panel.qml -d` →
  "Ignoring unresolvable import .../plugin/Commons" + "Configuration Loaded".
- Lotus supervision finding: no 31-log grep artifact exists; qmllint does not
  confirm missing-module; T-014 must be runtime-tested before routing to dev.
- Companion ADR-0011 (T-019): `anchors.fill` on `KeyboardPanel` — code-verified,
  routed to dev independently of this HELD import question.
- APPLICATION_SPEC.md §13 (#20).
