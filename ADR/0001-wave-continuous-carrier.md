# ADR-0001: WAVE — a third GPU/ShaderEffect visual (continuous-carrier mode)

- **Status:** Accepted (shipped in v7.6)
- **Date:** 2026-08-19
- **Deciders:** architect (this ADR); implemented by dev; verified by tester/reviewer under T-002
- **Referenced by:** `APPLICATION_SPEC.md` §10
- **Supersedes:** none · **Superseded by:** none

## 1. Context

v7.5 shipped the GPU/ShaderEffect renderer (`VisualCanvasGL.qml` + `visual.qsb`)
driven by a single GLSL fragment shader that selected between **two** visuals via
a control-texture row: Bar (analyzer, code 0) and Oscilloscope (envelope, code 1).

Product direction ("ref 06 — wave spirit") asked for a **Wave** look: a woven
field of *always-present* flowing lines that flex with the music but never
collapse into sparse dots at silence. The team chose to extend the existing
single-shader, multi-mode dispatch to a **third** mode (code 2) rather than add
a second shader file. This ADR records that decision and its invariants so
future visuals/backends stay consistent with `APPLICATION_SPEC.md` §10.

## 2. Decision

1. **One shared shader, 3-mode dispatch.** `visual.frag` decodes the visual
   selector from control-texture **row 2 R** as an 8-bit integer
   `int(ctrl().r * 255.0 + 0.5)`:
   - `0` = **Bar** (Winamp spectrum bars / fire post-process)
   - `1` = **Oscilloscope** (audio-envelope sine)
   - `2` = **Wave** (continuous flowing ribbon field)
   `VisualCanvasGL.qml` packs `cVisual`: `Wave→2`, `Oscilloscope→1`, else `0`.
2. **Wave is a continuous-carrier visual.** Each ribbon line is drawn at a
   constant base amplitude (`carrier * 0.13`) so it is **always visible even at
   silence**; the live spectrum modulates the line as an **additive** swing
   (`env * 0.55 * react`) on top of the carrier. This deliberately avoids the
   "sparse dots at silence" failure mode that triggered T-002's re-confirmation.
   Per ref 06, music only *flexes* the lines; it never breaks them.
3. **Audio-reactivity model.** Overall loudness `E = mean(bandAt(k/15) for k in
   0..15)`; `react = smoothstep(0.0, 0.55, E)`. `NW = 24` ribbons (`const int`,
   GLSL ES-3.10 safe), each with a depth-scaled frequency/phase; the envelope is
   a 3-tap `bandAt()` smooth of the local spectrum. Theme color sourced from
   `cTop()/cBot()` (Omarchy accent ramp, `THEME_PALETTE.md`).
4. **No new shader file, no engine change.** Wave reuses the same
   `density×12` control texture and the same `nbVal()` (bar-count) mechanism as
   Bar/Oscilloscope. The audio engine is orthogonal and unchanged. This preserves
   the "one compiled shader" architecture from spec §10.
5. **Dynamic bar count (`density`).** The GL renderer generalizes the bar count
   to `density` (desktop-window default **128**; `Desktop.qml` overrides it to
   `desktop.density`). The control texture is `density×12`, not a fixed 32×12.
   `barGap` (row 11 G, 0..1 of one bar slot) controls separation: 0.0 =
   contiguous immersive spectrum (desktop default), ~0.10 = slim gaps.

## 3. Consequences

**Positive**
- One shader to maintain; Wave ships without touching the engine or adding a
  shader-compile step. Matches the established "flat 2D, theme-sourced" product
  direction (spec §10).

**Negative / gaps (tracked as roadmap items)**
- **Panel dropdown does not expose Wave.** `Panel.qml`'s VISUALIZATION selector
  only offers `["Bar","Oscilloscope"]`. To use Wave the user must hand-edit
  `[desktop] visual = "wave"` in `config.toml`. → roadmap #16.
- **`visuals/wave.toml` params are inert.** The toml declares
  `amplitude/frequency/brightness/peak_fall`, but the Wave shader branch ignores
  them (it computes its own `freq/phase` from `depth` + `meta().r`). Either wire
  them as control-texture rows or trim the toml. → roadmap #17.
- **Two "Wave" concepts.** The Canvas-2D legacy fallback (`VisualCanvas.qml`)
  also has a "Wave" style; it is unrelated to the GL WAVE visual (spec §8
  disambiguates).
- **`visualFull` / `[full]` config** is read by `Model.js` but never consumed by
  any widget — dead config; leave or remove later (non-blocking).

**Documentation**
- `APPLICATION_SPEC.md` bumped v7.5 → v7.6 to record the 3-mode dispatch,
  `density×12` texture, `barGap`, and the WAVE rationale (this ADR is the
  authority referenced by spec §10).

## 4. Alternatives considered

- **Separate `wave.frag` + `wave.qsb`.** Rejected: doubles the shader-compile
  surface, diverges from the "single shared shader" architecture, and the
  wgpu/Mesa segfault history makes extra GLSL files riskier.
- **Make Wave a sub-mode of Oscilloscope.** Rejected: the always-on continuous
  carrier is a fundamentally different visual language from the envelope-following
  oscilloscope; overloading one branch would force branch-on-branch conditionals
  and blur the spec's "shipped visuals" contract.
- **Drive Wave lines from a real time-domain waveform.** Rejected: the engine
  emits a 32-band magnitude spectrum, not PCM; reconstructing a waveform is out of
  scope, and the continuous-carrier design already satisfies ref 06.

## 5. Open items / follow-ups

- Roadmap #16: expose Wave in the settings-panel VISUALIZATION selector.
- Roadmap #17: wire or remove `visuals/wave.toml` params.
- Disambiguate GL "Wave" vs Canvas-2D "Wave" in spec §8 (done in v7.6 bump).
