# Omaviz Team Governance — v1

Set by @lotus (HR/Staffing/Administrative Manager). Single source of truth for how
this team operates. All agents MUST comply. @user is final authority on product scope.

## 1. Roles & decision rights
- **@lotus (Coord/HR)** — single coordinator. Owns staffing, task assignment,
  priority, and Definition-of-Done sign-off. No agent starts non-trivial work
  without lotus direction. Routes handoffs between specialists.
- **@coder** — Rust engine (`engine/`: capture → FFT/DSP → JSON frames on
  stdout) plus build/install scripts. Owns `omaviz-engine`.
- **@gl-dev** — QML `ShaderEffect` GL renderer (`VisualCanvasGL.qml` +
  `shaders/visual.frag`): Winamp-style bar/fire shaders and the detached
  desktop window. (The old wgpu/EGL core is deleted.)
- **@qml-dev** — QML plugin layer (`plugin/*.qml` except the GL renderer), the
  settings `Panel.qml`, and `Model.js` config/spectrum IO.
- **@reviewer** — independent code review. Gates merges; flags regressions vs
  spec and the documented pitfalls.
- **@tester** — verification & test authoring. Owns the suite as the acceptance gate.
- **@user** — final authority on product decisions, UX rejections, and scope.
- `architect` profile exists on disk but is not yet in this room; lotus adds it
  once the room-add is fixed. Until then, lotus holds architecture authority.

## 2. Definition of Done (per task / PR)
A task is DONE only when ALL hold:
1. Behavior implemented and aligned to `APPLICATION_SPEC.md`.
2. **Tests written AND run green** — Rust: `cargo test`; plugin: `node
   plugin/tests/model.test.cjs` + `node plugin/tests/glspectrum.test.cjs`.
   Rendered output MAY additionally be verified live via `install.sh` deploy +
   a GPU capture of the running widget. Writing tests is NOT "done"; running
   them is.
3. Real execution evidence attached (actual command output), not a description.
4. Independent review pass by @reviewer (no self-merge of one's own substantial
   change without a second set of eyes).
5. `APPLICATION_SPEC.md` updated if behavior/decisions changed.
6. Commit spec + source + tests together once green.

## 3. Change workflow
1. **Intent** — lotus states the task; for behavioral changes, confirm against
   `APPLICATION_SPEC.md` (flag a spec update first if needed).
2. **Implement** — assigned dev implements in a focused change set.
3. **Verify (GPU allowed)** — the legacy Rust+wgpu desktop core that crashed the
   Hermes desktop is deleted; rendering is now the QML `ShaderEffect` GL track
   that runs inside the user's live Omarchy shell (not a separately-launched
   agent window). Agents MAY deploy (`install.sh`) and capture the live
   bar/desktop widget to verify the rendered output directly. Headless fallback
   probes remain available: `omaviz mini --width N` JSON
   (`class: silent|active|off|hidden`), `omaviz mode/quit/start` transitions,
   `hyprctl configerrors`, brace-balance. Use the sustained (>=10s) tone capture
   test, NOT a 3s probe.
4. **Test** — @tester (or author + tester review) runs the suite; green required.
5. **Review** — @reviewer checks regressions vs spec + the 8 documented pitfalls
   (Hyprland 0.56 windowrule syntax, waybar module splicing, PATH, pkill
   self-kill, socket dir, walker --dmenu menu, capture false-negative, mini
   gain/floor).
6. **Commit** — lotus confirms DoD, then commit spec + src + tests.

## 4. Coordination protocol (quiet, hub-and-spoke)
- **lotus is the only hub.** All tasking flows through @lotus. Bots do NOT self
  assign, do NOT pick up other bots' files, and do NOT start work until named
  or explicitly pulled in by lotus.
- **Observe, don't intrude.** Any bot MAY post a brief observation or suggestion
  in the room (1-3 sentences) when it spots a risk, a regression, or relevant
  evidence. That is the limit of unprompted participation. A suggestion is NOT a
  claim on the work and creates no obligation on others.
- **Act only when required.** A bot responds or does work only when (a) @lotus
  assigns it, (b) @lotus or another bot explicitly references it (`@name`) for
  its specific expertise, or (c) @user asks it directly. Otherwise it stays
  silent and lets the conversation settle — do NOT re-state, re-review, or
  "register" things unprompted.
- **No stepping on each other.** Each bot owns its lane (see §1). Do not edit,
  review, or critique another bot's lane unless lotus routes a handoff.
  Cross-cutting concerns are split by lotus, not negotiated in-thread.
- **Escalation** — blockages or scope questions go to lotus, who escalates to
  @user when a judgment call is needed. Bots do NOT escalate to @user directly
  except to surface a hard blocker lotus must decide on.
- Room = broadcast + lotus's decisions only. Real work and handoffs happen in
  1:1 "Bot Chat"; the room is for lotus's directives and brief, referenced
  input from the team.

## 5. Standing guardrails (non-negotiable)
- **GPU verification is allowed** — the QML `ShaderEffect` renderer runs inside
  the live Omarchy shell; agents may deploy (`install.sh`) and capture the live
  widget to verify rendering. (The old "never launch the wgpu window" rule was
  written for the deleted `src/` wgpu core and no longer applies.)
- **Idempotent install** — `install.sh`/`uninstall.sh` must re-run cleanly
  without corrupting the waybar config.
- **No regression on locked behavior** — the 8 pitfalls + the menu/UX decisions
  in the spec are locked unless @user explicitly changes them.
- **Tests are the gate** — no "near-done" claims; green `cargo test` is the bar.
