const assert = require("assert")
const GL = require("../glspectrum.js")

let passed = 0
function test(name, fn) { fn(); passed++; console.log("  ok -", name) }

// v7.1: GPU uniforms are packed from the live spectrum (TDD anchor for VisualCanvasGL)
// ===========================================================================
test("packBands: stretches shorter bands by nearest neighbor (fills display)", () => {
  const out = GL.packBands([0.5], 4)
  assert.strictEqual(out.length, 4)
  assert.deepStrictEqual(out, [0.5, 0.5, 0.5, 0.5])
})

test("packBands: downsamples by nearest when bands longer than n", () => {
  const bands = [0, 0.25, 0.5, 0.75, 1.0, 0.5, 0.25, 0]
  const out = GL.packBands(bands, 4)
  assert.strictEqual(out.length, 4)
  // index 0 -> bands[0]=0, 1 -> bands[2]=0.5, 2 -> bands[4]=1.0, 3 -> bands[6]=0.25
  assert.strictEqual(out[0], 0)
  assert.strictEqual(out[1], 0.5)
  assert.strictEqual(out[2], 1.0)
  assert.strictEqual(out[3], 0.25)
})

test("packBands: clamps out-of-range values", () => {
  const out = GL.packBands([-2, 5, NaN, 0.3], 4)
  assert.strictEqual(out[0], 0)
  assert.strictEqual(out[1], 1)
  assert.strictEqual(out[2], 0)
  assert.strictEqual(out[3], 0.3)
})

test("packBands: empty/undefined -> all zeros (no shader poison)", () => {
  assert.deepStrictEqual(GL.packBands([], 4), [0, 0, 0, 0])
  assert.deepStrictEqual(GL.packBands(undefined, 4), [0, 0, 0, 0])
})

test("peakOf: returns max packed value", () => {
  assert.strictEqual(GL.peakOf([0, 0.2, 0.9, 0.4]), 0.9)
  assert.strictEqual(GL.peakOf([]), 0)
})

test("packFire: true -> 1.0 (control-texture row 8 on)", () => {
  assert.strictEqual(GL.packFire(true), 1.0)
  assert.strictEqual(GL.packFire(false), 0.0)
})

test("fireOn: mirrors visual.frag decode (row 8 > 0.5 == on)", () => {
  assert.strictEqual(GL.fireOn(GL.packFire(true)), true)
  assert.strictEqual(GL.fireOn(GL.packFire(false)), false)
  // any value > 0.5 reads as on (matches QML cFire*255 -> 1.0)
  assert.strictEqual(GL.fireOn(1.0), true)
  assert.strictEqual(GL.fireOn(0.0), false)
})

// v7.2 (TASK #3 fix): the fire palette in shaders/visual.frag MUST be
// theme-sourced (cBot/cTop, seeded from THEME_PALETTE.md: Matte Black
// accent #e68e0d -> bright_blue #f59e0b) and MUST NOT hardcode the old
// amber/red ramp. GLSL can't run under node, so we assert the contract on
// the shader source: theme refs present, old hardcoded ramp absent.
const fs = require("fs")
const path = require("path")
const frag = fs.readFileSync(path.join(__dirname, "..", "shaders", "visual.frag"), "utf8")
test("fire palette is THEME-SOURCED (constraint 4): references cBot/cTop", () => {
  // fireColor() body must consume the theme gradient rows
  assert.ok(frag.includes("vec3 fireColor"), "fireColor() defined")
  const body = frag.slice(frag.indexOf("vec3 fireColor"))
  assert.ok(body.includes("cBot()"), "fireColor references themeBottom (cBot)")
  assert.ok(body.includes("cTop()"), "fireColor references themeTop (cTop)")
})
test("fire palette does NOT hardcode the old amber/red ramp", () => {
  assert.ok(!frag.includes("vec3(1.0, 0.85, 0.3)"), "old amber base gone")
  assert.ok(!frag.includes("vec3(1.0, 0.25, 0.05)"), "old red tip gone")
})
// The GL renderer seeds the theme texture (rows 6/7) from THEME_PALETTE.md
// (Matte Black: accent -> bright_blue). The shader consumes those same rows
// via cBot()/cTop(). Cross-check the QML defaults actually DERIVE from the
// palette file (parse it, don't hardcode the expected hex) and that nothing
// falls back to the legacy teal/purple.
const GLQML = fs.readFileSync(path.join(__dirname, "..", "VisualCanvasGL.qml"), "utf8")
const MODELJS = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8")
const PALETTE = fs.readFileSync(path.join(__dirname, "..", "..", "THEME_PALETTE.md"), "utf8")

// Pull a hex value out of a THEME_PALETTE.md table row whose key cell == `key`.
function paletteHex(text, key) {
  for (const line of text.split("\n")) {
    const cells = line.split("|").map(s => s.trim()).filter(Boolean)
    if (cells.includes(key)) {
      const m = line.match(/#[0-9A-Fa-f]{6}/)
      if (m) return m[0].toLowerCase()
    }
  }
  return null
}

test("THEME_PALETTE.md: Matte Black accent/bright_blue resolve to the seeded viz defaults", () => {
  const accent = paletteHex(PALETTE, "accent")
  const brightBlue = paletteHex(PALETTE, "bright_blue")
  assert.strictEqual(accent, "#e68e0d", "palette accent must equal seeded themeBottom")
  assert.strictEqual(brightBlue, "#f59e0b", "palette bright_blue must equal seeded themeTop")
})

test("theme palette defaults derive from THEME_PALETTE.md (Matte Black)", () => {
  const accent = paletteHex(PALETTE, "accent")
  const brightBlue = paletteHex(PALETTE, "bright_blue")
  // QML + Model.js seeds must agree with the palette (parsed, not hardcoded)
  assert.ok(new RegExp('themeBottom:\\s*"' + accent + '"').test(GLQML),
    "VisualCanvasGL.qml themeBottom seeded from palette accent")
  assert.ok(new RegExp('themeTop:\\s*"' + brightBlue + '"').test(GLQML),
    "VisualCanvasGL.qml themeTop seeded from palette bright_blue")
  assert.ok(new RegExp('themeBottom:\\s*"' + accent + '"').test(MODELJS),
    "Model.js defaultConfig.themeBottom matches palette accent")
  assert.ok(new RegExp('themeTop:\\s*"' + brightBlue + '"').test(MODELJS),
    "Model.js defaultConfig.themeTop matches palette bright_blue")
  // shader consumes those rows and never hardcodes the old teal/purple
  assert.ok(frag.includes("cBot()") && frag.includes("cTop()"),
    "shader consumes theme rows (cBot/cTop)")
  assert.ok(!frag.includes("#19e0d4") && !frag.includes("#a45cff"),
    "no legacy teal/purple hex in shader")
})

console.log(`\nℹ tests ${passed}`)

test("density generalization: packBands length follows density (dense > mini's 32)", () => {
  const dense = 64
  const out = GL.packBands([0.5, 0.25, 0.75], dense)
  assert.strictEqual(out.length, dense, "packBands produces a density-wide array")
  assert.ok(dense > 32, "desktop density is denser than the 32-band mini feed")
  assert.ok(out.every(v => v >= 0 && v <= 1), "all packed values normalized 0..1")
})

test("density generalization: shader NB rides in control row 11 (R=density/256)", () => {
  // VisualCanvasGL.qml must paint density into row 11 R (no free-standing uniform).
  assert.ok(GLQML.includes("Math.round(root.density / 256.0 * 255)"),
    "QML paints density into control-texture row 11")
  assert.ok(frag.includes("nbVal()"),
    "shader derives bar count from control-texture row 11 (nbVal)")
  assert.ok(!frag.includes("uniform float u_nb"),
    "no free-standing uniform (qsb Vulkan rejects it)")
})

test("barGap packs into control-texture row 11 G (0 = contiguous dense)", () => {
  // glspectrum.js exposes packGap, mirroring the QML paint (clamp 0..1 *255).
  assert.strictEqual(GL.packGap(0.0), 0.0, "0 gap stays 0 (immersive desktop)")
  assert.strictEqual(GL.packGap(0.10), 0.10, "default mini gap preserved")
  assert.strictEqual(GL.packGap(-1), 0.0, "negative clamped to 0")
  assert.strictEqual(GL.packGap(2), 1.0, "over-range clamped to 1")
  assert.strictEqual(GL.packGap(NaN), 0.0, "NaN -> 0")
  // QML paints barGap into row 11 G.
  assert.ok(GLQML.includes("root.barGap"),
    "VisualCanvasGL.qml references the barGap property in packing")
  assert.ok(/row\(11, Math\.round\(root\.density \/ 256\.0 \* 255\), Math\.round\(Math\.min\(1, Math\.max\(0, root\.barGap\)\) \* 255\)/.test(GLQML),
    "QML packs density (R) and barGap (G) into row 11")
  // Shader reads gap from the same row 11 G channel.
  assert.ok(frag.includes("scopeRow().g"),
    "shader reads barGap from control-texture row 11 G")
})

test("visual decode rides raw 0/1/2 in ctrl().r (no *2 collision with Wave)", () => {
  // VisualCanvasGL.qml must write cVisual RAW (0 analyzer /1 scope /2 wave).
  assert.ok(/row\(2, cVisual, cColorSrc\*255, 0\)/.test(GLQML),
    "QML paints cVisual raw into row 2 R (not *255)")
  assert.ok(/cVisual: \(visual === "Wave"\) \? 2 : \(visual === "Oscilloscope"\) \? 1 : 0/.test(GLQML),
    "cVisual maps Wave->2, Oscilloscope->1, Bars->0")
  // Shader decodes with *255 so 0/1/2 survive (was *2 -> 2 collided).
  assert.ok(frag.includes("int(ctrl().r * 255.0 + 0.5)"),
    "shader decodes visual as int(ctrl().r*255+0.5) (distinct 0/1/2)")
  assert.ok(frag.includes("else if (visual == 2)"),
    "shader has a dedicated WAVE branch (visual == 2)")
  // WAVE ribbon loop must be bounded (no unbounded dynamic loop in GLSL ES).
  assert.ok(frag.includes("const int NW = 24"),
    "WAVE ribbon loop is bounded (const int NW = 24)")
})

test("control-texture source uses NEAREST sampling (smooth:false, decode-race guard)", () => {
  // Control rows pack discrete 8-bit codes. Linear filtering would average
  // neighbouring rows (e.g. animated time row) and corrupt decode. Qt6 uses
  // `smooth: false` for nearest sampling.
  assert.ok(/id:\s*specTex[\s\S]*?smooth:\s*false/.test(GLQML),
    "specTex must set smooth: false for exact control-cell decode")
})

test("WAVE is audio-reactive: continuous carrier modulated by bandAt envelope", () => {
  assert.ok(frag.includes("else if (visual == 2)"), "WAVE branch exists")
  // Continuous line carrier (sin) so ribbons are ALWAYS woven, never scattered dots.
  assert.ok(/float carrier = sin\(uv\.x \* freq \+ phase\)/.test(frag), "ribbon is a continuous sine carrier")
  // Spectrum MODULATES the line as an ADDITIVE swing on top of the always-visible
  // carrier (env * react), so the line never scales to ~0 and collapses to dots.
  assert.ok(frag.includes("+ env * 0.55 * react"), "spectrum adds an audio swing on top of the carrier")
  // Carrier is added at a FIXED always-on amplitude (carrier * 0.13) — it is NOT
  // multiplied by a silence-floor, so ribbons stay continuous even on a quiet feed.
  assert.ok(frag.includes("carrier * 0.13"), "carrier always-visible (no loud-floor multiply)")
  // Old broken pattern removed: line positioned directly from multiplied amp that
  // collapsed to points on a sparse/sweep feed.
  assert.ok(!frag.includes("float amp = (0.05 + 0.55 * (1.0 - depth)) * (0.55 + 0.9 * env) * loud"),
    "old multiplied-amp (dashes) removed")
  assert.ok(!frag.includes("float loud  = 0.35 + 1.10 * drive"), "old loud-floor baseline removed")
})

console.log(`\nℹ pass ${passed}`)
console.log(`ℹ fail 0`)
