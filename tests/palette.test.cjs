"use strict";
const {test} = require("node:test");
const assert = require("node:assert/strict");
const {load} = require("./helpers.cjs");
const {build} = load("Palette.js");
const base = {r:190/255, g:20/255, b:0};
const tip = {r:253/255, g:224/255, b:71/255};
test("Flame retains its endpoints and ramp independently of other palettes", () => {
  const first = build([0,0,0], [1,1,1], base, tip);
  const second = build([0.1,0.2,0.3], [0.9,0,0.8], base, tip);
  assert.deepEqual(first.fire, second.fire);
  assert.equal(first.fire[0], "rgba(190,20,0,1)");
  assert.equal(first.fire[30], "rgba(255,130,10,1)");
  assert.equal(first.fire[100], "rgba(253,224,71,1)");
});
test("plain and wash gradients interpolate the same RGB values", () => {
  const palette = build([0,0,0], [1,1,1], base, tip);
  assert.equal(palette.plain.length, 101);
  assert.equal(palette.plain[50], "rgba(128,128,128,1)");
  assert.equal(palette.wash[50], "rgba(128,128,128,0.10)");
});
