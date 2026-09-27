// Perf regression guards for VisualCanvas.qml: the render hot path must
// stay allocation-light. These are static source checks, not benchmarks.
"use strict"
const fs = require("fs")
const path = require("path")
const { test } = require("node:test")
const assert = require("node:assert/strict")

const src = fs.readFileSync(path.join(__dirname, "..", "VisualCanvas.qml"), "utf8")
const desk = fs.readFileSync(path.join(__dirname, "..", "Desktop.qml"), "utf8")
const bar = fs.readFileSync(path.join(__dirname, "..", "BarWidget.qml"), "utf8")
const allQml = {
  qml: [src, desk, bar, fs.readFileSync(path.join(__dirname, "..", "Panel.qml"), "utf8")].join("\n")
}

test("palette LUTs exist (no per-bar QColor math)", () => {
  assert.ok(src.includes("_rebuildPalette"))
  assert.ok(src.includes("_fireLUT") && src.includes("_plainLUT") && src.includes("_washLUT"))
  // fillFor/fillWash must be LUT lookups — no Qt.darker/lighter inside them
  const fillFor = src.slice(src.indexOf("function fillFor"), src.indexOf("function fillWash"))
  assert.ok(!fillFor.includes("Qt.darker") && !fillFor.includes("Qt.lighter"))
  const fillWash = src.slice(src.indexOf("function fillWash"), src.indexOf("onPaint"))
  assert.ok(!fillWash.includes("Qt.darker") && !fillWash.includes("Math.round"))
})

test("one shared gradient per frame, never per bar", () => {
  assert.equal((src.match(/createLinearGradient/g) || []).length, 1)
  assert.ok(src.includes("sharedGrad"))
})

test("peaks + reflect + flat bodies batch into single fills", () => {
  assert.ok(src.includes("useFlat"))
  assert.ok(src.includes("if (useFlat) ctx.fill()"))
})

test("paint dedup skips pixel-identical frames", () => {
  for (const fn of ["_advancePhysics", "_computeSig", "_modeSig", "_maybePaint"]) {
    assert.ok(src.includes(fn), `missing ${fn}`)
  }
  assert.ok(src.includes("_lastBandsSig") && src.includes("_lastModeSig"))
  // hash storage must survive 32-bit (FNV-1a exceeds signed int range)
  assert.ok(src.includes("property double _lastBandsSig"))
  // wave-mode frames ignore spectrum data (scope paints from wave only)
  assert.ok(src.includes('if (visual === "Wave" || visual === "Oscilloscope") return'))
})

test("paint throttle caps rate, physics stays per-frame", () => {
  assert.ok(src.includes("_lastPaintMs"))
  assert.ok(src.includes("now - _lastPaintMs < 33"))
  // Physics is delegated to Physics.js and advances on data, independent of
  // the paint throttle. The accelerating peak fall (x1.05) lives there now.
  const adv = src.slice(src.indexOf("function _advancePhysics"), src.indexOf("function _modeSig"))
  assert.ok(adv.includes("Physics.step("), "advancePhysics must delegate to Physics.step")
  const phys = fs.readFileSync(path.join(__dirname, "..", "Physics.js"), "utf8")
  assert.ok(phys.includes("speeds[i] * 1.05"), "accelerating peak fall lives in Physics.js")
})

test("band mapping reuses scratch buffers (no per-frame alloc)", () => {
  assert.ok(src.includes("_bandBuf") && src.includes("_bandUp"))
  assert.ok(!src.includes("out.push(m)") && !src.includes("up.push("))
})

test("plain bars batch by color, flat/fire paths preserved", () => {
  // bucket collect + per-color flush (now uses shared gradient for all bars)
  assert.ok(src.includes("barBkt") && src.includes("barOrd.push(bkey)"))
  // single shared gradient for all bars (better perf than per-color LUT)
  assert.ok(src.includes("ctx.fillStyle = sharedGrad"))
  // mono/artMode single-fill path still intact for plain bars
  assert.ok(src.includes("} else if (useFlat) {"))
  assert.ok(src.includes("if (useFlat) ctx.fill()"))
  // fire gradient path still per-bar
  assert.ok(src.includes("ctx.fillStyle = sharedGrad"))
})

test("config poll skips parse when text unchanged", () => {
  assert.ok(desk.includes("_lastCfgText"))
  assert.ok(desk.includes("if (txt !== win._lastCfgText)"))
})

test("wave feed is scope-only with bridge restart on flip", () => {
  assert.ok(desk.includes('win.vizConfig.scope === true ? ["--wave"]'))
  assert.ok(desk.includes("_lastScope"))
})

test("every surface runs the SAME 60Hz feed (no decimation, no substeps)", () => {
  // The mini, the panel preview and the desktop window all feed VisualCanvas
  // at 60Hz, and physics has no rate-specific compensation — so the fall
  // trajectory is identical everywhere.
  assert.ok(!desk.includes("_frameSeq"), "desktop must not decimate frames")
  assert.ok(desk.includes("dataFps: 60"))
  assert.ok(src.includes("property real dataFps: 60"))
  assert.ok(!src.includes("var steps = dataFps > 45 ? 1 : 2"), "no substep hack")
  assert.ok(!allQml.qml.includes("--fall-mode"), "no spawn-time physics flag")
})

test("wash paints overlap-free analytic columns", () => {
  // no 2x-wide rects anymore; stacked alpha derived from single alpha
  assert.ok(!src.includes("gw * 2"))
  assert.ok(src.includes("1 - (1 - wa) * (1 - wa)"))
  assert.ok(src.includes("hasPrv"))
})

test("paint reuses maybe-paint hash via frame-stamped stash", () => {
  assert.ok(src.includes("_stashFrame = _frameId; _stashValid = true"))
  assert.ok(src.includes("_frameId++"))
  assert.ok(src.includes("if (_stashFrame === _frameId"))
})

test("artwork blur is cached (static source)", () => {
  assert.ok(desk.includes("cached: true"))
})
