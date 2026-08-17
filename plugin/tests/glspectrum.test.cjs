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

console.log(`\nℹ tests ${passed}`)
console.log(`ℹ pass ${passed}`)
console.log(`ℹ fail 0`)
