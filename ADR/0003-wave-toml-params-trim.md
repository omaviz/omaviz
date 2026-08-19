# ADR-0003: Trim inert `visuals/wave.toml` parameters (decision: trim, not wire)

| | |
|---|---|
| **Status** | Accepted (to implement in v7.6.x) |
| **Date** | 2026-08-19 |
| **Author** | architect (@architect) |
| **Task** | T-008 (roadmap #17) |
| **Applies to** | `plugin/visuals/wave.toml`, `plugin/Model.js` (per-visual param plumbing for wave), `plugin/shaders/visual.frag` (WAVE branch), `plugin/VisualCanvasGL.qml` |
| **Supersedes** | none |
| **Superseded by** | none |

## 1. Context

`plugin/visuals/wave.toml` declares four user-facing parameters:

```toml
[[params]]
name = "amplitude"   # 0.1 .. 1.5, default 0.7
name = "frequency"   # 0.2 .. 3.0, default 1.0
name = "brightness"  # 0.1 .. 1.0, default 0.6
name = "peak_fall"   # 0.0 .. 1.0, default 0.3
```

These are surfaced by `Model.visualParamsFromText` / `visualConfigValues` and
written under `[visual.wave]` in `config.toml`. **However, the WAVE branch in
`visual.frag` does not read any of them.** It computes ribbon geometry entirely
from `depth` (the loop index) and the time uniform `meta().r`:

```glsl
float freq  = 4.0 + depth * 9.0;                       // NOT from wave.toml frequency
float phase = meta().r * (0.5 + depth * 0.7) * 6.2831 + depth * 2.5;
float carrier = sin(uv.x * freq + phase);
float yw = baseY + carrier * 0.13 + env * 0.55 * react; // amplitude 0.13 hard-coded
```

So `amplitude`, `frequency`, `brightness`, and `peak_fall` are **inert**: a user
changing them in the panel produces no visible change in the GL Wave visual.
This is a spec/code contradiction (roadmap #17).

## 2. Decision

**Option (b): trim — remove the params and the spec claim that wave.toml drives
the shader.** Do *not* wire them into the WAVE shader (rejected as option (a),
see §4).

### 2.1 `visuals/wave.toml`
Reduce the file to a pure mode descriptor — **drop the entire `[[params]]`
block** (all four params). Keep:

```toml
name = "wave"
label = "Wave"
description = "Continuous woven sine-ribbon field (GL). Geometry is computed in-shader; no tunable params."
```

### 2.2 `Model.js`
The generic per-visual param plumbing (`visualParamsFromText`,
`visualConfigValues`, the `[visual.<name>]` write-back) is shared and stays —
it is still used by `equalizer`/`oscilloscope`/etc. where applicable. But
because `wave.toml` no longer declares params, `visualParamsFromText(waveToml)`
yields an empty list, so no `wave.*` knobs are generated in the panel and no
`[visual.wave]` section is written. **No special-case code is needed** — the
trim is achieved by emptying the param block; the shared machinery harmlessly
produces nothing for `wave`.

### 2.3 `visual.frag` / `VisualCanvasGL.qml`
No shader change required by this ADR — the WAVE branch already ignores the
params. (Row 10 R stays `alpha`; no new control row is added.) The continuous-
carrier design (ADR-0001) is the reason the params are meaningless, which is
exactly why we trim rather than wire.

### 2.4 Spec correction
APPLICATION_SPEC.md §10 WAVE bullet now states the geometry is computed in-
shader from `depth` + `meta().r` and is **not** driven by `wave.toml` params
(already edited under T-007 pass). The roadmap #17 entry is marked Shipped with
the "trim, not wire" decision.

## 3. Consequences

- **Positive:** removes a silent contradiction — users can no longer "tune"
  knobs that do nothing. The panel shows no Wave param section (correct, since
  none exist).
- **Positive:** zero shader/control-texture churn; aligns with the deliberate
  continuous-carrier design (ADR-0001) that requires in-shader geometry to keep
  ribbons continuous at all loudness.
- **Negative / cost:** users lose the *ability* to tune Wave amplitude/freq/
  brightness. This is accepted: the continuous-carrier aesthetic (always-
  present woven lines) is the intended product look, and per-ribbon variation is
  already driven by `depth` + time, giving organic motion without user knobs. If
  product later wants tunables, that is a new ADR (would require the additive-
  swing wiring described in §4, with care to not reintroduce the collapse bug).
- **Test gate (tester):** add an assertion that `parseVisualToml(waveToml).
  params` is empty (no `amplitude`/`frequency`/`brightness`/`peak_fall`), and
  that `visualConfigValues` for wave yields no entries. Regression-guard against
  someone re-adding inert params.

## 4. Rejected alternative — option (a): wire params into the shader

Wiring `amplitude`/`frequency`/`brightness`/`peak_fall` would require new
control-texture rows (e.g. row 10 G/B/A, or a new row 12) carrying the four
floats, plus `packBands`-style packers in `glspectrum.js` and QML paint calls.
Rejected because:

1. **Conflict with ADR-0001.** The continuous-carrier design *depends* on
   `carrier * 0.13` being an always-on fixed amplitude. Making amplitude a
   user multiplier (`carrier * amp`) reintroduces the exact pre-v7.6 collapse
   risk (quiet feed → near-zero amplitude → lines break into dots). `frequency`
   as a user scalar would fight the `4.0 + depth*9.0` per-ribbon spread that
   gives the woven look. `brightness`/`peak_fall` overlap with existing
   `alpha`/peak-hold controls already present on other branches.
2. **Cost vs benefit.** Four new control rows + packers + QML paint + tests for
   a visual whose whole point is a fixed, music-modulated aesthetic. The
   benefit (user tuning) is low and contradicts the design intent.
3. **Row-10 budget.** Row 10 is already reserved (see ADR-0004); burning its
   channels on four Wave knobs would collide with the `alpha`-row reservation
   policy and complicate the spec.

## 5. References
- `plugin/visuals/wave.toml` — current four `[[params]]` blocks (to be removed).
- `plugin/Model.js` — `visualParamsFromText`, `visualConfigValues`.
- `plugin/shaders/visual.frag` — WAVE branch (`else if (visual == 2)`).
- `ADR/0001-wave-continuous-carrier.md` — why in-shader geometry is mandatory.
- `ADR/0004-oscilloscope-width-row10.md` — row 10 reservation policy.
- APPLICATION_SPEC.md §10 (WAVE bullet), §13 (#17).
