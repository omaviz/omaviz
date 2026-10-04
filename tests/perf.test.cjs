// Architectural guards; resource and frame budgets require the native probe.
"use strict"
const fs = require("fs")
const {test} = require("node:test")
const assert = require("node:assert/strict")
const path = require("path")
const read = f => fs.readFileSync(path.join(__dirname,"..",f),"utf8")
const src = read("VisualCanvas.qml")

test("all surfaces share the native geometry renderer", () => {
  for (const f of ["BarWidget.qml","Panel.qml","Desktop.qml"])
    assert.ok(read(f).includes("VisualCanvas {"), f)
  assert.ok(src.includes("Native.VisualGeometry {"))
  assert.ok(!src.includes('getContext("2d")'))
  assert.ok(!src.includes("requestPaint()"))
})
test("display clock owns fixed-step physics without 33ms paint throttle", () => {
  assert.ok(src.includes("FrameAnimation {"))
  assert.ok(src.includes("cv.advance(1000 / 60)"))
  assert.ok(src.includes("Math.min(frameTime * 1000, 100)"))
  assert.ok(!src.includes("_lastPaintMs"))
  assert.ok(src.includes("cv.visible && cv._awake"))
})
test("geometry retains buffers and avoids full-surface image uploads", () => {
  const native = read("renderer/geometry.cpp")
  assert.ok(native.includes("QSGGeometry::DynamicPattern"))
  assert.ok(native.includes("count > capacity || indexCount > indexCapacity"))
  assert.ok(!native.includes("QImage"))
})
test("desktop keeps feed ownership and config dedup", () => {
  const desk = read("Desktop.qml")
  assert.ok(desk.includes("_lastCfgText"))
  assert.ok(desk.includes("if (txt !== win._lastCfgText)"))
  assert.ok(desk.includes('win.vizConfig.visual !== "Bars" ? ["--wave"]'))
  assert.ok(!desk.includes("_frameSeq"))
  assert.ok(desk.includes("cached: true"))
})
