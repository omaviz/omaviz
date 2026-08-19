# ADR-0005: Control-texture NEAREST filtering (T-013, the real WAVE decode-race fix)

- **Status:** Accepted (spec for T-013)
- **Date:** 2026-08-19
- **Lane:** architect (this ADR) → dev (impl) → tester (GPU capture) → reviewer (grade)
- **Referenced by:** `APPLICATION_SPEC.md` §10 (control-texture filtering note), §13 (roadmap #19)
- **Supersedes:** the `filtering: ShaderEffectSource.Nearest` prescription in ADR-0001 §3.2 / spec §10 (that prescription is **invalid** in Qt 6.x — see §2)

## 1. Context

The control texture (`specTex`, a `ShaderEffectSource` of `specCanvas`, `density×12`)
packs discrete 8-bit codes: `ctrl().r` carries the visual selector `0/1/2`
(Bars/Oscilloscope/Wave). To decode these exactly, the texture must be sampled
with **NEAREST** (point) filtering — LINEAR averaging would blend the packed
`2/255` with neighbouring rows (notably the animated `time` row 3) so Wave
(`2`) decodes as `~1` → the Oscilloscope branch. ADR-0001 and spec §10
prescribed `filtering: ShaderEffectSource.Nearest` to force this.

**That prescription is wrong for Qt 6.** Confirmed from the installed Qt 6.11.1
tree on this box:

- `/usr/lib/qt6/qml/QtQuick/plugins.qmltypes` → `QQuickShaderEffectSource`
  property list is exactly: `wrapMode, sourceItem, sourceRect, textureSize,
  format, live, hideSource, mipmap, textureMirroring, samples`. **No
  `filtering` property exists.**
- `/usr/include/qt6/QtQuick/6.11.1/QtQuick/private/qquickshadereffectsource_p.h`
  `Q_PROPERTY` block (lines 47–57) confirms the same set; `grep -i filtering`
  on that header returns **nothing**.
- `QQuickShaderEffect` (`qquickshadereffect_p.h`) likewise exposes **no**
  `texture` / `filtering` property (`grep` on the header returns nothing).
  So the alternative `fx.u_tex.filtering: Nearest` is **also** invalid (the
  earlier architect draft that suggested it must NOT be applied).

Consequence: in the current `3afa086` deploy, `VisualCanvasGL.qml:147`
`filtering: ShaderEffectSource.Nearest` is a **silent no-op** (QML prints
"Cannot assign to non-existent property 'filtering'" and ignores it), so the
control texture is **LINEAR**. This is the real reason the desktop/WAVE visual
mis-renders even after a clean reinstall — and it is independent of the stale
`visual.qsb` (11317→11168) issue. Tester logged it as **T-013** and withheld
T-002/T-003 visual sign-off until fixed.

## 2. Decision

Force NEAREST on the control texture through the **only QML-facing mechanism**:
render `specCanvas` (the `ShaderEffectSource.sourceItem`) through a **layer**
with smoothing off.

```qml
// in VisualCanvasGL.qml, on the source Item that specTex samples:
specCanvas.layer.enabled: true
specCanvas.layer.smooth: false   // false => QSGTexture::Nearest for this layer's texture
```

Rationale / evidence:

- `QQuickItemLayer` (`plugins.qmltypes`, exports `QtQuick/ItemLayer 2.9`…`6.7`)
  exposes exactly two writable props: `enabled: bool` and `smooth: bool`.
  `smooth: false` is the documented Qt6 knob that makes an item's layer texture
  sample with NEAREST instead of LINEAR.
- When `sourceItem` is a layer-enabled item, `ShaderEffectSource` reuses that
  item's already-rendered FBO texture (NEAREST), so the shader's `texture(u_tex,
  …)` fetches land on exact cell centers — restoring correct `0/1/2` decode.
- This is the only path that does not require a C++ `QQuickItem` subclass to
  call `QSGTexture::setFiltering(Nearest)` (that C++ API is real but not
  QML-exposed). The C++ subclass is kept as a **fallback only** if the layer
  path proves insufficient under a real GPU capture (tester's T-013 sign-off).

### 2.1 Removal / replacement of the broken line

- **Delete** `VisualCanvasGL.qml:147` `filtering: ShaderEffectSource.Nearest`
  (it both warns and does nothing).
- **Add** `specCanvas.layer.enabled: true; specCanvas.layer.smooth: false`
  (on the `Canvas`/`Item` that `specTex.sourceItem` points at).

### 2.2 Test correction (must accompany the source change)

`plugin/tests/glspectrum.test.cjs` lines 176–185 currently assert the **broken**
form:

```js
assert.ok(/ShaderEffectSource\s*\{[\s\S]*?id:\s*specTex[\s\S]*?filtering:\s*ShaderEffectSource\.Nearest/.test(GLQML),
  "specTex (control texture) must set filtering: ShaderEffectSource.Nearest")
```

This test **passes today** (glspectrum 18/0) while validating a no-op — it
matches source text, not behaviour. Replace it with an assertion that the
**correct** mechanism is present on the source item:

```js
test("control texture uses NEAREST via sourceItem.layer.smooth:false (Qt6, T-013)", () => {
  // ShaderEffectSource has no `filtering` property in Qt6; the only QML-facing
  // way to force point sampling is layer.enabled + layer.smooth:false on the
  // sourceItem. Without it the packed visual code 2/255 averages with the time
  // row and Wave silently decodes as Oscilloscope.
  assert.ok(/layer\.enabled:\s*true/.test(GLQML), "sourceItem must enable layer")
  assert.ok(/layer\.smooth:\s*false/.test(GLQML), "sourceItem layer must be smooth:false (NEAREST)")
  assert.ok(!/ShaderEffectSource\.Nearest/.test(GLQML),
    "ShaderEffectSource.Nearest is invalid in Qt6 — must not be used")
})
```

The dev owns this test edit (architect does not touch source). The corrected
test fails against `3afa086` and passes once the layer fix lands.

## 3. Consequences

**Positive**
- Restores exact `0/1/2` control-code decode → Wave renders as Wave (not
  Oscilloscope), and the Bar-fire/peaks toggles (`>0.5`) stay exact.
- Pure QML change; no engine, no new shader compile, no binary rebuild.
- Removes a spurious runtime warning ("Cannot assign to non-existent property
  'filtering'").

**Negative / gaps**
- Depends on `layer.smooth:false` actually driving the SES-reused texture under
  the user's real Mesa/wgpu stack — must be confirmed by tester's GPU capture
  (T-002/T-003 sign-off), not just by the unit test matching text.
- If the layer path proves insufficient, fall back to a tiny C++ `QQuickItem`
  exposing `QSGTexture::setFiltering(Nearest)` — out of scope for T-013 v1.

## 4. Alternatives considered

- **`filtering: ShaderEffectSource.Nearest` (current/ADR-0001)** — rejected:
  property does not exist in Qt6; silent no-op + warning.
- **`fx.u_tex.filtering: Nearest` (earlier architect draft)** — rejected:
  `ShaderEffect` exposes no `texture`/`filtering` property.
- **`specTex.texture.filtering` / `specTex.filtering`** — rejected: neither is
  exposed (verified in qmltypes + headers).
- **Custom C++ `QQuickItem` calling `QSGTexture::setFiltering(Nearest)`** —
  viable but heavier; reserved as fallback only.

## 5. Follow-ups

- Roadmap #19 (T-013): implement + verify the layer fix under a real GPU
  capture; release only after tester sign-off.
- ADR-0001 §3.2 and spec §10's "uses `ShaderEffectSource.Nearest`" wording must
  be corrected to the layer mechanism (done in the same spec patch as this ADR).
