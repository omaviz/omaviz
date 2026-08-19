# omaviz — Agent Task Board

Maintained by: lotus. Policy: AGENT_GOVERNANCE.md.

## Active tasks
| ID | Title | Owner(s) | Status | Notes |
|----|-------|----------|--------|-------|
| T-001 | APPLICATION_SPEC v7.x review (spec/code consistency) | architect (spec fix) → dev (version bump) → reviewer (re-grade) | IN PROGRESS — architect DONE + reviewer PASS (2026-08-19, gates green: cargo 34 / model 55 / glspectrum 17 / barwidget 11); dev executing v7.6 tag + live-plugin copy | reviewer: spec/code contradiction RESOLVED, all gates green; surfaced roadmap gaps #16/#17/#18 (logged T-007/T-008/T-009). |
| T-002 | WAVE GL visual re-confirmation | dev (impl) / tester (QA) | BLOCKED / needs user GPU approval | Code fix verified (visual.frag continuous carrier). Live GL capture needs explicit user pre-approval. |
| T-003 | Settings-panel popup visual proof | dev / tester | BLOCKED / needs live shell | Panel.qml present (code-verified). Standalone harness can't surface shell-layer popup; needs user's running Omarchy shell. |
| T-004 | Telegram delivery config | user | BLOCKED / needs creds | No telegram configured in tester profile; artifacts on disk only. |
| T-007 | Wave missing from panel VISUALIZATION selector (#16) | architect (spec) → dev (Panel.qml) → tester → reviewer | OPEN / needs spec | Wave usable only via hand-edited `[desktop] visual="wave"`; Panel.qml options are Bar/Oscilloscope. Dev-lane source edit. |
| T-008 | wave.toml params inert in Wave shader (#17) | architect (spec) → dev (wire/trim) → tester → reviewer | OPEN / needs spec | amplitude/frequency/brightness/peak_fall not read by visual.frag Wave branch (computes own freq/phase). |
| T-009 | Oscilloscope line-width alpha-G input dead (#18, P3) | architect (spec) → dev → tester → reviewer | OPEN / needs spec | visual.frag:191 reads alphaRow().g*0.02 but row 10 G packed 0; width pinned to 0.004 floor. Pre-existing, non-gating. |
| T-005 | Roster consolidation | lotus | DONE | gl-dev/qml-dev/coder merged into `dev`; old profiles retired 2026-08-19. |
| T-006 | Governance policy + task board | lotus | DONE | AGENT_GOVERNANCE.md + this board created 2026-08-19. |

## Closed
- T-005 roster consolidation — done.
- T-006 governance + task board — done.

## Rules
- One owner-per-phase (architect→dev→tester→reviewer per task).
- No source edits outside `dev`.
- GPU launch only with explicit per-capture user approval.
- Evidence required for every status change.
