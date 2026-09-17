// Perf regression guards for VisualCanvas.qml: the render hot path must
// stay allocation-light. These are static source checks, not benchmarks.
"use strict"
const fs = require("fs")
const path = require("path")
const { test } = require("node:test")
const assert = require("node:assert/strict")

const src = fs.readFileSync(path.join(__dirname, "..", "VisualCanvas.qml"), "utf8")
const desk = fs.readFileSync(path.join(__dirname, "..", "Desktop.qml"), "utf8")

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
  for (const fn of ["_advancePhysics", "_computeSig", "_modeSig", "_maybePaint", "_sizePeaks"]) {
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
  // physics advances on data, independent of paint throttle
  const adv = src.slice(src.indexOf("function _advancePhysics"), src.indexOf("function _modeSig"))
  assert.ok(adv.includes("_peakSpeed[i] * 1.05"))
})

test("band mapping reuses scratch buffers (no per-frame alloc)", () => {
  assert.ok(src.includes("_bandBuf") && src.includes("_bandUp"))
  assert.ok(!src.includes("out.push(m)") && !src.includes("up.push("))
})

test("plain bars batch by color, flat/fire paths preserved", () => {
  // bucket collect + per-color flush
  assert.ok(src.includes("barBkt") && src.includes("barOrd.push(bkey)"))
  assert.ok(src.includes("ctx.fillStyle = _plainLUT[bk2]"))
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

test("feed decimated to 30Hz with physics compensation", () => {
  // bridge skips odd frames; canvas runs 2 physics substeps at 30Hz
  assert.ok(desk.includes("win._frameSeq++"))
  assert.ok(desk.includes("(win._frameSeq & 1) === 0) return"))
  assert.ok(desk.includes("dataFps: 30"))
  assert.ok(src.includes("property real dataFps: 60"))
  assert.ok(src.includes("var steps = dataFps > 45 ? 1 : 2"))
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
