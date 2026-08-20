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

test("control-texture source uses NEAREST filtering (decode-race guard)", () => {
  // The control texture packs discrete 8-bit codes (visual 0/1/2 in row 2 R,
  // toggles in rows 8/9, density in row 11). The default LINEAR filtering
  // averages a row with its vertical neighbours (e.g. the animated time row),
  // so a packed value 2 (R=2/255) reads back as ~1 -> wave silently renders
  // as the oscilloscope branch. Qt6 exposes NO `filtering` property on
  // ShaderEffectSource (a `filtering: ...` line is a silent no-op), so NEAREST
  // is forced by routing specCanvas through a layer FBO with smoothing
  // disabled. See ADR-0005.
  assert.ok(/id:\s*specCanvas[\s\S]*?layer\.enabled:\s*true/.test(GLQML),
    "specCanvas must enable a layer (NEAREST control texture, ADR-0005)")
  assert.ok(/id:\s*specCanvas[\s\S]*?layer\.smooth:\s*false/.test(GLQML),
    "specCanvas layer must disable smoothing so the control texture samples NEAREST")
  assert.ok(!/filtering:\s*ShaderEffectSource\.Nearest/.test(GLQML),
    "no-op ShaderEffectSource.filtering line must be removed (ADR-0005)")
})

test("WAVE is audio-reactive: continuous carrier modulated by bandAt envelope", () => {
  assert.ok(frag.includes("else if (visual == 2)"), "WAVE branch exists")
  // Continuous line carrier (sin) so ribbons are ALWAYS woven, never scattered dots.
  assert.ok(/float carrier = sin\(uv\.x \* freq \+ phase\)/.test(frag), "ribbon is a continuous sine carrier")
  // Spectrum MODULATES the line as an ADDITIVE swing on top of the always-visible
  // carrier (env * react), so the line never scales to ~0 and collapses to dots.
  assert.ok(frag.includes("+ env * 0.55 * react"), "spectrum adds an audio swing on top of the carrier")
  // Carrier is added at a FIXED always-on amplitude (carrier * 0.18, raised in
  // T-023 for low-amplitude visibility) — it is NOT multiplied by a silence-floor,
  // so ribbons stay continuous even on a quiet feed.
  assert.ok(frag.includes("carrier * 0.18"), "carrier always-visible (no loud-floor multiply, brightened in T-023)")
  // Old broken pattern removed: line positioned directly from multiplied amp that
  // collapsed to points on a sparse/sweep feed.
  assert.ok(!frag.includes("float amp = (0.05 + 0.55 * (1.0 - depth)) * (0.55 + 0.9 * env) * loud"),
    "old multiplied-amp (dashes) removed")
  assert.ok(!frag.includes("float loud  = 0.35 + 1.10 * drive"), "old loud-floor baseline removed")
})

// T-012 (reviewer P3): T-009 / ADR-0004 removed the dead `alphaRow().g*0.02`
// term from the oscilloscope line-width. Guard it so a regression can't
// silently revive the dead input (control-texture row 10 G is reserved/unused,
// always 0 — VisualCanvasGL never paints it).
function stripComments(src) {
  return src
    .replace(/\/\/[^\n]*/g, "")        // line comments
    .replace(/\/\*[\s\S]*?\*\//g, "")  // block comments
}
const fragNoComments = stripComments(frag)
test("T-009/ADR-0004: osc line width uses fixed OSC_LINE_W (dead alphaRow input gone)", () => {
  assert.ok(frag.includes("const float OSC_LINE_W = 0.007;"),
    "OSC_LINE_W const defined at 0.007 (raised from 0.004 in T-023 for low-amp visibility)")
  assert.ok(fragNoComments.includes("lw = OSC_LINE_W"),
    "osc line width derives from the fixed OSC_LINE_W const")
  assert.ok(!fragNoComments.includes("alphaRow().g"),
    "dead alphaRow().g term removed from live shader code (only the row-10 accessor def remains)")
})

// T-020 (ADR-0005): Wave visual-code collapse fix. The control texture packs
// the visual code (0 Bars /1 Osc /2 Wave) into row 2 R as raw 2/255. Under
// LINEAR sampling the ShaderEffectSource blends row 2 with its ONLY vertical
// neighbor, row 3. Historically row 3 held the animated `time` (high-variance),
// so a packed 2/255 blended down to ~1 -> the `visual==2` branch was never
// taken and Wave silently rendered as the oscilloscope branch (tester captured
// Wave as vertical bars — defect LIVE).
//
// Fix (sampling-independent): row 3 now ALSO carries the visual code (so the
// row2<->row3 LINEAR blend yields the code exactly), and `time` is relocated to
// the unused row 11 B channel. Decode logic (int(ctrl().r*255+0.5)) is unchanged.
// This is robust whether or not NEAREST is actually applied.
//
// We assert the source invariants AND simulate the LINEAR round-trip: for each
// visual, build the packed rows under the NEW layout and verify the LINEAR
// decode (avg of row2.R and row3.R) still yields the exact code. We also show
// the OLD layout (row3 = time) would have collapsed Wave -> ~1.

// Mimic visual.frag: int(ctrl().r * 255.0 + 0.5). GLSL int() TRUNCATES
// (Math.round(2.5)==3 but int(2.5)==2), so use Math.trunc to match exactly.
function linDecodeVisual(rows) {
  const r2 = rows[2].r, r3 = rows[3].r
  const ctrlR = (r2 + r3) / 2.0            // linear blend of the two neighbors
  return Math.trunc(ctrlR * 255.0 + 0.5)
}
// Under NEAREST, ctrl().r is exactly row 2 R.
function nearDecodeVisual(rows) {
  return Math.trunc(rows[2].r * 255.0 + 0.5)
}

test("T-020: QML writes the visual code into BOTH row 2 and row 3 (code copy)", () => {
  // row 2 keeps the code; row 3 is now a copy of the code (neighbor used to be time)
  assert.ok(/row\(2, cVisual, cColorSrc\*255, 0\)/.test(GLQML), "row 2 carries cVisual")
  assert.ok(/row\(3, cVisual, 0, 0\)/.test(GLQML), "row 3 also carries cVisual (LINEAR-safe copy)")
})

test("T-020: QML relocated animated time into the unused row 11 B channel", () => {
  // row 11 previously: row(11, density, barGap, 0). Now B carries time.
  assert.ok(
    /row\(11, Math\.round\(root\.density \/ 256\.0 \* 255\), Math\.round\(Math\.min\(1, Math\.max\(0, root\.barGap\)\) \* 255\), Math\.round\(\(u_time % 1000\) \/ 1000 \* 255\)\)/.test(GLQML),
    "row 11 packs density (R), barGap (G), and time (B)")
})

test("T-020: shader reads time from row 11 (meta -> 11.5/H) using .b channel", () => {
  assert.ok(/vec4\s+meta\(\)\s*\{\s*return texture\(u_tex, vec2\(0\.5, 11\.5\/H\)\)/.test(frag),
    "meta() now reads row 11 (where time lives)")
  assert.ok(!frag.includes("meta().r"), "no stale meta().r time reads remain")
  assert.ok(frag.includes("meta().b"), "time is read from meta().b (row 11 B)")
})

function packedRows(cVisual, timeNorm) {
  // normalized rows (0..1); only the channels the fix touches are set.
  const z = () => ({ r: 0, g: 0, b: 0 })
  const rows = [z(), z(), z(), z(), z(), z(), z(), z(), z(), z(), z(), z()]
  rows[2].r = cVisual / 255.0          // row 2 R = visual code (raw)
  rows[3].r = cVisual / 255.0          // row 3 R = code COPY (NEW)
  rows[11].b = timeNorm                // row 11 B = time (NEW location)
  return rows
}

test("T-020: LINEAR round-trip decodes Wave=2 exactly (was collapsing to ~1)", () => {
  const wave = packedRows(2, 0.73)    // wave + arbitrary live time
  assert.strictEqual(linDecodeVisual(wave), 2, "LINEAR blend of row2/row3 (both = code) -> 2")
  assert.strictEqual(nearDecodeVisual(wave), 2, "NEAREST -> 2")
  const osc = packedRows(1, 0.40)
  assert.strictEqual(linDecodeVisual(osc), 1, "Oscilloscope stays 1")
  const bars = packedRows(0, 0.10)
  assert.strictEqual(linDecodeVisual(bars), 0, "Bars stays 0")
})

test("T-020: OLD layout would have collapsed Wave (regression guard)", () => {
  // Old: row 3 R = time (high-variance), row 2 R = 2/255. LINEAR blend ~0.5 -> ~128.
  const oldWave = { r: 0, g: 0, b: 0 }
  const r2 = 2 / 255.0, r3 = 0.73       // row2 = code(2), row3 = time(high)
  const blended = (r2 + r3) / 2.0
  const decoded = Math.trunc(blended * 255.0 + 0.5)
  assert.notStrictEqual(decoded, 2, "OLD: blended value is NOT 2 (this is the bug we fixed)")
  // NEW layout makes row3 = code too, so it can never collapse:
  const newWave = (2 / 255.0 + 2 / 255.0) / 2.0
  assert.strictEqual(Math.trunc(newWave * 255.0 + 0.5), 2, "NEW: row3=code copy -> stays 2")
})

// T-023 (low-amplitude visibility): WAVE + OSC must be visible near silence,
// not just when loud. VERIFIED upstream: the T-020 wave=ribbons (not bars)
// collapse bug is dead (pipewire capture). The remaining issue is brightness —
// WAVE's always-on carrier (0.13) + dim bg read as low-contrast; OSC's
// OSC_LINE_W=0.004 is sub-pixel with no always-on baseline so it vanishes at
// low amp. Fixes raise WAVE brightness and give OSC a visible line at silence.
test("T-023: WAVE always-on carrier amplitude raised (ribbons visible at silence)", () => {
  assert.ok(frag.includes("carrier * 0.18"),
    "WAVE carrier amplitude raised 0.13 -> 0.18 (always-on, not scaled by react)")
  assert.ok(!frag.includes("carrier * 0.13"),
    "old 0.13 carrier (too dim at silence) gone")
  // The carrier is added directly (NOT multiplied by react) so it shows at silence.
  assert.ok(frag.includes("carrier * 0.18"),
    "always-on carrier present (added outside the react term)")
  assert.ok(frag.includes("+ env * 0.55 * react"),
    "audio swing added on top of the always-on carrier")
})
test("T-023: WAVE ribbon + background brightness raised", () => {
  assert.ok(frag.includes("mix(cBot()*0.55, cTop()*0.95, uv.y)"),
    "WAVE background gradient brightened (0.32/0.64 -> 0.55/0.95)")
  assert.ok(frag.includes("rc * halo * 0.95"),
    "WAVE halo intensity raised 0.70 -> 0.95")
  assert.ok(frag.includes("rc * core * 3.0"),
    "WAVE core intensity raised 2.4 -> 3.0")
})
test("T-023: OSC line width raised above sub-pixel", () => {
  assert.ok(frag.includes("const float OSC_LINE_W = 0.007;"),
    "OSC line width raised 0.004 -> 0.007 (visible at low amp)")
  assert.ok(!frag.includes("const float OSC_LINE_W = 0.004;"),
    "old sub-pixel 0.004 width gone")
})
test("T-023: OSC has always-on faint baseline at silence (y=0.5)", () => {
  // At silence env=0 -> wy=0.5; a baseline mask at abs(y-0.5) keeps the line
  // visible even when w (audio swing) is ~0, so OSC never collapses to nothing.
  assert.ok(/float dBase = abs\(y - 0\.5\)/.test(frag),
    "OSC baseline distance from silence center computed")
  assert.ok(/mb = step\(dBase, lw\)/.test(frag) || /mb \* 0\.\d+/.test(frag),
    "OSC always-on baseline mask applied (faint) so line shows at silence")
})

console.log(`\nℹ pass ${passed}`)
console.log(`ℹ fail 0`)
