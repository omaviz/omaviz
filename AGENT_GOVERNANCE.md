# omaviz Agent Team — Governance Policy

Effective: 2026-08-19. Owner: lotus (HR/Staffing/Administrative Manager).

## Authority model (single-source-of-truth)
| Role | Sole authority over | Must NOT do |
|------|--------------------|-------------|
| **architect** | specs, technical roadmap, architectural solutions, technical decisions (ADRs) | edit source, run QA, grade |
| **dev** | ALL source-code changes (`.rs`, `.qml`, `.frag`, `.js`, `.toml`, build scripts). Merged Rust-engine + QML/GLSL viz. | write specs, create tests, grade |
| **tester** | test cases + QA artifacts (screenshots, REPORT.md, pixel analyses, integration harness) | edit source, grade |
| **reviewer** | GRADING — dev's source AND tester's QA artifacts | edit source, write specs |
| **lotus** | staffing, task board, handoffs, admin | build / test / verify the app; issue contradictory mandates |

## Change flow (per task)
1. **architect** writes/updates spec or ADR, assigns task ID.
2. **lotus** logs task on `AGENT_TASKS.md`; assigns dev (impl) + tester (QA) + reviewer (grade).
3. **dev** implements to spec, commits, reports done + any requested test evidence.
4. **tester** builds test cases, captures artifacts, reports PASS/FAIL with real evidence.
5. **reviewer** grades code + artifacts → APPROVE / REWORK.
6. **lotus** tracks to closure. No task left in perpetual "open sign-off".

## Hard rules
- **Single committer.** Only `dev` edits source. Proposals from others route via spec/bug report; dev implements. Eliminates overlapping edits.
- **GPU launch.** `tester` may launch GPU/Wayland surfaces ONLY under (a) explicit user pre-approval for that specific capture, or (b) a user-approved test plan. No agent may assert "approved" on its own authority.
- **Evidence, not claims.** Every PASS/VERIFIED cites real tool output or an artifact path. No fabricated delivery (e.g. Telegram requires configured creds; if absent, report the blocker — do not invent success).
- **No self-contradiction (lotus).** One directive per topic. If uncertain, ask the user; never emit conflicting mandates (e.g. "GREEN LIGHT" then "STOP").
- **Task board.** lotus maintains `AGENT_TASKS.md`. Every task: ID, owner, status. No duplicate work.
- **Reviewer SLA.** Grades within 3 handoffs of assignment or escalates to user. No perpetual open sign-off.

## Roster
- `dev` — merged implementation agent (supersedes gl-dev, qml-dev, coder)
- `tester` — QA + artifacts
- `reviewer` — grader (code + artifacts)
- `architect` — specs / roadmap / architecture / decisions
- `lotus` — HR / staffing / coordination / admin

Superseded (retire): gl-dev, qml-dev, coder.
