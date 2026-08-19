# ADR-0004: Oscilloscope line-width dead input + control-texture row 10 reservation

| | |
|---|---|
| **Status** | Accepted (to implement in v7.6.x) |
| **Date** | 2026-08-19 |
| **Author** | architect (@architect) |
| **Task** | T-009 (roadmap #18, P3) |
| **Applies to** | `plugin/shaders/visual.frag` (Oscilloscope branch, line ~191), `plugin/VisualCanvasGL.qml` (row 10 paint), APPLICATION_SPEC.md §10 control-row table |
| **Supersedes** | none |
| **Superseded by** | none |

## 1. Context

In the Oscilloscope branch of `visual.frag`:

```glsl
float lw = (alphaRow().g * 0.02) + 0.004;   // line width
...
float m = step(d, lw);
```

`alphaRow()` reads control-texture **row 10**. But `VisualCanvasGL.qml` packs
row 10 as:

```js
row(10, Math.round(Math.min(1, Math.max(0, alpha))*255), 0, 0)   // R=alpha, G=0, B=0, A=0
```

The `G` channel of row 10 is **always `0`**. Therefore `alphaRow().g * 0.02`
is always `0`, and the line width reduces to the constant `0.004` floor. The
`*0.02` term is a **dead input** — changing nothing the user can reach.

Additionally, APPLICATION_SPEC.md's control-row table (and the QML header
comment) documented row 10 as `R=alpha(0..1)  G=unused  B=unused  A=unused` —
the word "unused" is misleading: it implies the G/B/A channels are free to be
read, when in fact the shader's Oscilloscope branch *attempts* to read `G` but
gets a constant zero. The correct state is: **row 10 is reserved** (only `R`
is defined/used as `alpha`; `G/B/A` are reserved and must stay `0`).

## 2. Decision

**Drop the dead input; mark row 10 reserved.** Do *not* wire `alphaRow().g` to
a real control (rejected alternative, see §4).

### 2.1 `visual.frag` (Oscilloscope branch)
Remove the `*0.02` dead term; line width becomes the fixed constant:

```glsl
float lw = 0.004;   // fixed oscilloscope line width (row 10 G is reserved; see ADR-0004)
```

The comment in the shader should note that width is intentionally constant and
not a user knob. Line detail is already controlled by `density` (bar/ribbon
count) and the `peaks` toggle on this branch.

### 2.2 `VisualCanvasGL.qml` (row 10 paint)
No change needed to the paint — it already writes `row(10, alpha*255, 0, 0)`.
But the **header comment** for row 10 must be corrected from "G=unused B=unused
A=unused" to "G/B/A = reserved (must stay 0)". This documents intent and
prevents a future dev from packing a value into G and expecting the
oscilloscope to read it (it won't, post-fix).

### 2.3 Spec correction (APPLICATION_SPEC.md §10)
- The control-row table row 10 entry: `R=alpha(0..1)  G=reserved  B=reserved
  A=reserved` (was "unused").
- The §10 Oscilloscope bullet gains a "Line width (T-009 / ADR-0004)" note
  explaining the dead term was removed and width is fixed `0.004` (already
  edited under this task).
- Roadmap #18 marked Shipped with the "drop dead term, mark row 10 reserved"
  decision.

## 3. Consequences

- **Positive:** removes dead code and a misleading spec/comment; the
  oscilloscope renders identically to before (width was already effectively
  `0.004`), so this is a pure cleanup with **zero visual change**.
- **Positive:** the reserved-row10 policy is now explicit, preventing future
  misuse of the G/B/A channels.
- **Negative / cost:** users cannot adjust oscilloscope line thickness. Accepted
  (P3): the `density`/`peaks` controls already modulate line detail, and a
  thickness knob would need a new control row or a packed channel — not worth it
  for a legacy-ish branch.
- **Test gate (tester):** add a `glspectrum.test.cjs` assertion that the
  Oscilloscope branch no longer references `alphaRow().g * 0.02` (regex
  negative: `!frag.includes("alphaRow().g * 0.02")`) and that a fixed `0.004`
  width constant is present. Regression-guard against reintroduction.

## 4. Rejected alternative — wire `alphaRow().g` to a real control

We could make line width a real user knob by, e.g., packing a `scopeWidth` into
row 10 G (or a new row 12) and reading it in the shader. Rejected because:

1. **Row-10 budget.** Row 10 is now **reserved** (only `R`=alpha is defined).
   Burning G for scope width breaks the reservation policy and collides with the
   alpha-row convention used by the Bar/Fire branches.
2. **Low value (P3).** Oscilloscope line detail is already governed by
   `density` (number of evaluated points) and the `peaks` toggle. A separate
   thickness slider is marginal polish, not a defect.
3. **New control plumbing.** Any real knob needs a `packScopeWidth` in
   `glspectrum.js`, a QML paint call, a `Model` config key, and panel UI — all
   for a P3 nicety. The dead-input cleanup is strictly better ROI.

If product later wants tunable scope width, that is a new ADR (would allocate a
dedicated control row, e.g. row 12, not reuse reserved row 10).

## 5. References
- `plugin/shaders/visual.frag` — Oscilloscope branch (`else` of the visual
  dispatch), line-width computation.
- `plugin/VisualCanvasGL.qml` — `row(10, ...)` paint; header comment.
- `ADR/0003-wave-toml-params-trim.md` — sibling cleanup (row-10 reservation
  consistency).
- APPLICATION_SPEC.md §10 (control-row table, Oscilloscope bullet), §13 (#18).
