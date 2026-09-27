// Physics.js tests — run: node --test tests/physics.test.cjs
//
// The renderer's motion model must be verified by assertions, not by eye:
//   * instant attack
//   * rate-limited release (bars FALL when audio stops, never vanish)
//   * peak caps hold for peakSustainMs then fall with an accelerating speed
//   * noise floor zeroes inaudible targets
"use strict"
const fs = require("fs")
const path = require("path")
const { test } = require("node:test")
const assert = require("node:assert/strict")

function loadPhysics() {
  const src = fs.readFileSync(path.join(__dirname, "..", "Physics.js"), "utf8")
  const js = src.replace(/^\.pragma library\s*/, "")
  const module = { exports: {} }
  new Function("module", "exports", js)(module, module.exports)
  return module.exports
}
const P = loadPhysics()

const DT = 1000 / 60            // ms per frame at 60 Hz
const opts = (over = {}) => Object.assign(
  { linearFall: true, peakFalloff: 0.1, peakSustainMs: 100, noiseFloor: 0 }, over)

function arrays(n, barsFill = 0, peaksFill = 0, targetsFill = 0) {
  return {
    bars: new Array(n).fill(barsFill),
    peaks: new Array(n).fill(peaksFill),
    holds: new Array(n).fill(0),
    speeds: new Array(n).fill(0),
    targets: new Array(n).fill(targetsFill),
  }
}

test("peakSpeed0 and barFallRate are monotonic in falloff and clamped", () => {
  assert.equal(P.peakSpeed0(-1), P.peakSpeed0(0))
  assert.equal(P.peakSpeed0(2), P.peakSpeed0(1))
  assert.ok(P.peakSpeed0(1) > P.peakSpeed0(0))
  assert.ok(P.barFallRate(1) > P.barFallRate(0))
  assert.ok(P.barFallRate(NaN) === P.barFallRate(0.1), "NaN falloff -> default 0.1")
})

test("attack is instant: the bar reaches the target on the same frame", () => {
  const a = arrays(1, 0, 0, 0.8)
  P.step(a.bars, a.peaks, a.holds, a.speeds, a.targets, DT, opts())
  assert.equal(a.bars[0], 0.8)
  assert.equal(a.peaks[0], 0.8)
})

test("release is rate-limited: bars FALL, they do not vanish when audio stops", () => {
  const a = arrays(1, 1.0, 1.0, 0.0)
  a.holds[0] = 0
  P.step(a.bars, a.peaks, a.holds, a.speeds, a.targets, DT, opts())
  const perFrame = P.barFallRate(0.1) * (DT / 1000)
  assert.ok(a.bars[0] > 0, "bar must still be visible one frame after silence")
  assert.ok(Math.abs(a.bars[0] - (1.0 - perFrame)) < 1e-9, `expected linear fall, got ${a.bars[0]}`)
  // It keeps falling frame by frame toward the target.
  const prev = a.bars[0]
  P.step(a.bars, a.peaks, a.holds, a.speeds, a.targets, DT, opts())
  assert.ok(a.bars[1 - 1] < prev)
})

test("release never overshoots past the target", () => {
  const a = arrays(1, 0.02, 0.02, 0.0)
  P.step(a.bars, a.peaks, a.holds, a.speeds, a.targets, DT, opts({ peakFalloff: 1 }))
  assert.equal(a.bars[0], 0, "must clamp to target, not go negative")
})

test("exponential release also falls and clamps", () => {
  const a = arrays(1, 1.0, 1.0, 0.0)
  for (let i = 0; i < 120; i++) P.step(a.bars, a.peaks, a.holds, a.speeds, a.targets, DT, opts({ linearFall: false }))
  assert.ok(a.bars[0] < 0.05, `exp release should reach near zero, got ${a.bars[0]}`)
  assert.ok(a.bars[0] >= 0)
})

test("peak cap HOLDS for peakSustainMs before it starts to fall", () => {
  const o = opts({ peakSustainMs: 100 })
  const sustainFrames = Math.round(100 / DT) // 6
  const a = arrays(1, 1.0, 1.0, 1.0)
  // one frame at target 1.0 sets the cap + hold counter
  P.step(a.bars, a.peaks, a.holds, a.speeds, a.targets, DT, o)
  assert.equal(a.peaks[0], 1.0)
  assert.equal(a.holds[0], sustainFrames)
  // now audio stops: cap must stay pinned for the whole hold window
  a.targets[0] = 0
  for (let i = 0; i < sustainFrames; i++) {
    P.step(a.bars, a.peaks, a.holds, a.speeds, a.targets, DT, o)
    assert.equal(a.peaks[0], 1.0, `cap must not fall during hold (frame ${i})`)
  }
  // the next frame it finally starts to fall
  P.step(a.bars, a.peaks, a.holds, a.speeds, a.targets, DT, o)
  assert.ok(a.peaks[0] < 1.0, "cap must fall once the sustain window elapses")
})

test("peak fall ACCELERATES (each frame drops more than the last)", () => {
  const o = opts({ peakSustainMs: 0, peakFalloff: 0.1 })
  const a = arrays(1, 1.0, 1.0, 1.0)
  P.step(a.bars, a.peaks, a.holds, a.speeds, a.targets, DT, o)
  a.targets[0] = 0
  let drops = []
  let last = a.peaks[0]
  for (let i = 0; i < 8; i++) {
    P.step(a.bars, a.peaks, a.holds, a.speeds, a.targets, DT, o)
    drops.push(last - a.peaks[0])
    last = a.peaks[0]
  }
  for (let i = 1; i < drops.length; i++) {
    assert.ok(drops[i] > drops[i - 1] - 1e-12, `drop ${i} (${drops[i]}) should exceed ${drops[i - 1]}`)
  }
  assert.ok(drops[drops.length - 1] > drops[0], "fall speed must grow over time")
})

test("cap never falls below the bar", () => {
  const o = opts({ peakSustainMs: 0, peakFalloff: 1 })
  const a = arrays(1, 0.5, 1.0, 0.5)
  a.holds[0] = 0
  for (let i = 0; i < 60; i++) {
    P.step(a.bars, a.peaks, a.holds, a.speeds, a.targets, DT, o)
    assert.ok(a.peaks[0] >= a.bars[0] - 1e-9, `cap ${a.peaks[0]} must stay >= bar ${a.bars[0]}`)
  }
})

test("noiseFloor treats inaudible targets as zero (no jitter bars)", () => {
  const a = arrays(1, 0, 0, 0.005)
  P.step(a.bars, a.peaks, a.holds, a.speeds, a.targets, DT, opts({ noiseFloor: 0.02 }))
  assert.equal(a.bars[0], 0, "sub-floor target must render as zero")
  // and a clearly audible target still shows
  a.targets[0] = 0.5
  P.step(a.bars, a.peaks, a.holds, a.speeds, a.targets, DT, opts({ noiseFloor: 0.02 }))
  assert.equal(a.bars[0], 0.5)
})

test("targets are clamped to 0..1 and NaN handled", () => {
  const a = arrays(3, 0, 0, 0)
  a.targets[0] = 5; a.targets[1] = -3; a.targets[2] = NaN
  P.step(a.bars, a.peaks, a.holds, a.speeds, a.targets, DT, opts())
  assert.equal(a.bars[0], 1)
  assert.equal(a.bars[1], 0)
  assert.equal(a.bars[2], 0)
})

test("settled() is false while falling and true once parked", () => {
  const a = arrays(2, 0, 0, 0)
  a.targets[0] = 1; a.targets[1] = 1
  P.step(a.bars, a.peaks, a.holds, a.speeds, a.targets, DT, opts())
  // bars == targets and caps == bars -> settled
  assert.equal(P.settled(a.bars, a.peaks, a.targets), true)
  // silence -> bars fall below target -> not settled until they land
  a.targets[0] = 0; a.targets[1] = 0
  P.step(a.bars, a.peaks, a.holds, a.speeds, a.targets, DT, opts())
  assert.equal(P.settled(a.bars, a.peaks, a.targets), false, "still falling => not settled")
  for (let i = 0; i < 400; i++) P.step(a.bars, a.peaks, a.holds, a.speeds, a.targets, DT, opts())
  assert.equal(P.settled(a.bars, a.peaks, a.targets), true, "after landing => settled")
})

test("ensure() resizes preserving existing values", () => {
  let a = P.ensure([], 3, 0)
  assert.deepEqual(a, [0, 0, 0])
  a[0] = 7
  a = P.ensure(a, 5, 0)
  assert.deepEqual(a, [7, 0, 0, 0, 0])
  a = P.ensure(a, 2, 0)
  assert.deepEqual(a, [7, 0])
})

test("all surfaces share one model: same inputs => same trajectory", () => {
  // mini (32 bands) and desktop (256 bands) with identical per-band targets
  // must produce identical per-band motion — no surface-specific physics.
  const mini = arrays(32, 0, 0, 0)
  const desk = arrays(256, 0, 0, 0)
  mini.targets.fill(0.7); desk.targets.fill(0.7)
  P.step(mini.bars, mini.peaks, mini.holds, mini.speeds, mini.targets, DT, opts())
  P.step(desk.bars, desk.peaks, desk.holds, desk.speeds, desk.targets, DT, opts())
  mini.targets.fill(0); desk.targets.fill(0)
  for (let i = 0; i < 50; i++) {
    P.step(mini.bars, mini.peaks, mini.holds, mini.speeds, mini.targets, DT, opts())
    P.step(desk.bars, desk.peaks, desk.holds, desk.speeds, desk.targets, DT, opts())
  }
  assert.equal(mini.bars[0], desk.bars[0])
  assert.equal(mini.peaks[0], desk.peaks[0])
})
