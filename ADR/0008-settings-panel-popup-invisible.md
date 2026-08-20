# ADR-0008: Settings-panel popup invisible (T-014) — IMPORT-RESOLUTION status OPEN (unverified)

| | |
|---|---|
| **Status** | **HELD — import-resolution question UNVERIFIED; needs controlled runtime load** |
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
2. **Empirically unconfirmed.** Runtime testing this session (§2) shows the import
   warning IS emitted, but Panel.qml logs **"Configuration Loaded"** — i.e. it does
   NOT hard-fail on the import. The causal claim "fails to load → never surfaces"
   is therefore NOT established. `qmllint plugin/Panel.qml` also does not flag an
   unresolvable-import error (it exited non-zero, but on a different basis — see §3).

T-014 is **HELD**: the import-resolution question must be tested at runtime (a real
QML engine load, or a controlled launch under user GPU/UI approval per
AGENT_GOVERNANCE.md) before any claim of confirmed root cause or any code change.

## 1. Context

The settings popup (Panel.qml → KeyboardPanel via qs.Ui PanelController) never
surfaces on left-click toggle. Two candidate causes were raised:
- (A) missing `qs.Commons`/`qs.Ui` modules (import resolution),
- (B) `anchors.fill` on `KeyboardPanel` (a `PanelWindow`, no `anchors` property) —
  this is **code-verified** (ADR-0011, T-019) and is routed to dev independently.

This ADR covers only (A), now HELD.

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
location is mismatched (path one level too deep). But whether this warning is the
*actual cause* of the popup never surfacing is **UNVERIFIED** — the config loads
despite it.

## 3. What qmllint shows (independent check, per lotus)

`qmllint plugin/Panel.qml` did NOT exit 0 and did NOT emit an "unresolvable import"
error — it exited non-zero on other grounds (the same run reported exit 255). So
qmllint does **not** confirm the missing-module cause either. Both static and the
above runtime evidence fail to confirm "import failure → panel never surfaces."

## 4. Remaining hypotheses (OPEN — not asserted)

- **(H-A1)** The unresolvable `qs.Commons`/`qs.Ui` import is fatal *only in the
  user's specific launch context* (e.g. when loaded as a child of the live shell
  via `BarWidget.detach()`, or under a different Quickshell build), producing a
  hard "module not installed" abort there even though the standalone `-p` load
  tolerated it as a warning. Needs the user's live repro to confirm.
- **(H-A2)** The import warning is benign and T-014's true cause is purely (B)
  `anchors.fill` (ADR-0011) — in which case fixing T-019 resolves T-014 and the
  module warning is a red herring. Plausible given "Configuration Loaded" despite
  the warning.
- **(H-A3)** The vendored `plugin/qs/` dir is a stale/partial working-tree artifact
  (it is untracked: `?? plugin/qs/`). Correct placement would be `plugin/Commons`
  and `plugin/Ui` (matching how `qs.Commons` resolves), or adding `plugin/` (or
  `plugin/qs/`) to the QML import path. If dev intended to vendor the modules, the
  current path is simply wrong and should be fixed regardless of T-014's cause.

## 5. Required next step BEFORE any code change (no source edits yet)

Do NOT let dev change import wiring or vendor location based on an unconfirmed
cause. Instead, run a **controlled runtime load on the user's live system** (under
user GPU/UI approval per AGENT_GOVERNANCE.md) and capture:

1. `quickshell -p plugin/Panel.qml -d` log: does it end in "Configuration Loaded"
   or "Failed to load configuration / module qs.Commons is not installed"?
2. The same, but launched as a child of the live shell via `BarWidget.detach()`
   (the user's actual failure path): does the popup surface or not, and what does
   the by-id log say about the import?
3. Whether fixing ONLY T-019 (`anchors.fill` removal, ADR-0011) makes the popup
   appear — if yes, H-A2 holds and the import warning is incidental.

Only after (1)-(3) should a specific module-resolution fix be specified.

## 6. Provisional spec for dev (CONDIAL — only after live repro)

If the repro confirms the import is fatal in-context (H-A1/H-A3), the fix is a
**path correction**, not a rewrite:
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
