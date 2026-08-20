# ADR-0010: Click mapping — left vs right button (T-016) — FLAGGED for user decision

| | |
|---|---|
| **Status** | **OPEN — awaiting user decision** (architect flags; does NOT unilaterally decide UX) |
| **Date** | 2026-08-19 |
| **Author** | architect (@architect) |
| **Task** | T-016 (roadmap #22) |
| **Applies to** | `plugin/BarWidget.qml` (WidgetButton `onPressed`, lines 252-255) |
| **Supersedes** | none |
| **Superseded by** | none |

## 1. Context

`BarWidget.qml` currently maps:
```qml
// BarWidget.qml:252-255
onPressed: function(b) {
  if (b === Qt.LeftButton)  root.toggle()   // settings panel
  else if (b === Qt.RightButton) root.detach()  // detached desktop window
}
```
i.e. **left-click = settings panel, right-click = detach desktop window.**

lotus relayed (second-hand, **unverified** — there is no direct user message
confirming it) that the user expects left-click = desktop (detach). The in-file
code comment at BarWidget.qml:246-251 records a *prior* explicit user intent that
left = settings panel, explicitly correcting an earlier misstatement that
left-click should open the desktop window. Per the spec-accuracy governance rule,
a sub-agent's relayed claim about user intent must be framed as **"needs
confirmation,"** not asserted as fact. There is a contradiction between the
recorded prior intent and the unverified relayed expectation; this must be
resolved by an **explicit user statement**, not assumed. Until the user answers,
the **current mapping (left = settings / right = detach) stands as the default** —
no UX change.

## 2. The two options

### Option A — keep current mapping (left=settings, right=detach)
- **Pros:** the settings panel is the most frequent interaction on a bar widget;
  a quick left-click to configure is the common Omarchy/Quickshell plugin
  convention (most bar widgets open config on left-click). Right-click as a
  "power" action (detach a standalone window) is a sensible secondary gesture.
- **Cons:** contradicts the user's stated current expectation (per lotus).

### Option B — swap to left=detach, right=settings
- **Pros:** matches the user's stated expectation; the big visual payoff
  (desktop spectrum window) is one primary-click away.
- **Cons:** settings become the "hidden" right-click; less conventional for bar
  widgets; the in-code comment claims the user *previously* wanted settings on
  left, so this may just be a re-reversal unless the user re-confirms.

## 3. Architect recommendation

**Recommend Option A (keep left=settings / right=detach)** as the *standing
default*, for two reasons: (1) it matches the prevailing bar-widget convention and
the most frequent task (configuration), and (2) the code comment records a prior
explicit user intent to that effect — so flipping it should require a *fresh,
explicit* user confirmation, not a relayed summary. If the user confirms they now
want left=detach, adopt Option B.

**This is a flag, not a decision.** The architect lane owns specs/architecture,
not unilateral UX calls that contradict recorded user intent. lotus must surface
the contradiction to the user and return the confirmed mapping before dev
implements.

**Spec-accuracy note (per governance):** this ADR states the "user expects
left=detach" expectation as *reported, unverified*, and keeps the current mapping
as the default until the user answers. No assertion of user intent is made as fact.

## 4. Spec for dev (CONDIAL — only after user decides)

Whichever mapping is confirmed, the implementation is a one-line swap in
`BarWidget.qml:252-255`:
- Option A (current): `LeftButton → root.toggle()`; `RightButton → root.detach()`.
- Option B (swap): `LeftButton → root.detach()`; `RightButton → root.toggle()`.

No other file changes; both `toggle()` (settings) and `detach()` (desktop window)
already exist and work independently (verified in BarWidget.qml:68-70, 161-179).

## 5. Consequences of either choice
- Both retain full functionality (settings reachable on one button, detach on the
  other); only the gesture assignment changes.
- Tooltip text (BarWidget.qml:241-242) and any docs must be updated to match the
  chosen mapping.

## 6. References
- `plugin/BarWidget.qml` — `onPressed` (252-255), `toggle()` (68-70),
  `detach()` (161-179), intent comment (246-251).
- APPLICATION_SPEC.md §7 (detach lifecycle), §13 (#21).
