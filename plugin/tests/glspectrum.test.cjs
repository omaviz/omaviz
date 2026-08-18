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
console.log(`ℹ pass ${passed}`)
console.log(`ℹ fail 0`)
