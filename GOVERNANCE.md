# Omaviz Team Governance

This document is RETIRED. The current, authoritative governance policy is
`AGENT_GOVERNANCE.md` (v2, set by @lotus on 2026-08-19).

Key corrections vs. this old v1 doc:
- The agent roster here (coder / gl-dev / qml-dev / reviewer / tester, architect
  pending) is OBSOLETE. Current roster: architect (specs/ADRs), dev (sole source
  editor, merged from coder+gl-dev+qml-dev), tester (QA artifacts), reviewer
  (grader of code + artifacts), lotus (staffing/coordination). See
  `AGENT_GOVERNANCE.md`.
- §5 of this old doc stated "GPU verification is allowed — agents MAY deploy and
  capture the live widget." That is REVOKED. Per `AGENT_GOVERNANCE.md`, a GPU/
  Wayland surface launch requires EXPLICIT per-capture USER pre-approval; no agent
  may assert approval on its own authority. The "safe to verify live" language
  below is likewise superseded.

Read `AGENT_GOVERNANCE.md` for the binding policy.
