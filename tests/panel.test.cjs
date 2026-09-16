// Panel.qml UI-contract tests — run: node --test tests/panel.test.cjs
// Static source checks for the settings-panel UX rules: single-line
// helpers, no slider sub-text, no BARS subtitle, boxed sliders, shared
// OPTIONS nav row, Fire+Linear pairing, input-gain label. Catches
// copy regressions that qmllint cannot see (it only checks syntax).
"use strict"
const fs = require("fs")
const path = require("path")
const { test } = require("node:test")
const assert = require("node:assert/strict")

const src = fs.readFileSync(path.join(__dirname, "..", "Panel.qml"), "utf8")

function descriptions() {
  const out = []
  const re = /description:\s*"([^"]*)"/g
  let m
  while ((m = re.exec(src)) !== null) out.push(m[1])
  return out
}

test("all toggle helper texts are single short liners", () => {
  const ds = descriptions()
  assert.ok(ds.length >= 8, `expected 8+ descriptions, got ${ds.length}`)
  for (const d of ds) {
    assert.ok(!d.includes("\\n"), `multiline helper: ${d}`)
    assert.ok(d.length <= 45, `helper too long (${d.length}): ${d}`)
  }
})

test("artwork helper uses the immersive wording", () => {
  assert.ok(src.includes('description: "Immersive artwork"'))
  assert.ok(!src.includes("Album art behind bars"))
})

test("slider helpers are gone (peak fall, input gain)", () => {
  assert.ok(!src.includes("0 holds"))
  assert.ok(!src.includes("Response for all viz"))
  assert.ok(!src.includes("Sensitivity\"\n") || src.includes('text: "Input gain"'))
  assert.ok(src.includes('text: "Input gain"'))
  assert.ok(!src.includes('text: "Sensitivity"'))
})

test("no BARS subtitle under OPTIONS", () => {
  assert.ok(!src.includes('text: "BARS"'))
})

test("sliders live in shell-styled boxes", () => {
  const boxes = (src.match(/BorderSurface \{/g) || []).length
  assert.ok(boxes >= 4, `expected 4+ BorderSurface boxes, got ${boxes}`)
  assert.ok(src.includes('borderSpec: Border.controlSpec("normal"'))
  assert.ok(src.includes("Style.controlFill(false, false,"))
})

test("no custom flat boxes remain", () => {
  // Only VizCard (unselected) + preview background may use the flat
  // popup fill; the 4 slider/color boxes must be BorderSurface.
  assert.equal((src.match(/Color\.popups\.background/g) || []).length, 2)
})

test("single shared OPTIONS nav row flips Advanced/Back", () => {
  assert.ok(src.includes('text: root.showAdvanced ? "« Back" : "Advanced »"'))
  assert.ok(src.includes("onClicked: root.showAdvanced = !root.showAdvanced"))
  // no standalone links left
  assert.ok(!src.includes('text: "Advanced »"\n'))
  assert.ok(!src.includes('text: "« Back"\n'))
  assert.ok(!src.includes('text: "ADVANCED"'))
})

test("Fire and Linear fall share one row", () => {
  const iFire = src.indexOf('label: "Fire"')
  const iLin = src.indexOf('label: "Linear fall"')
  assert.ok(iFire !== -1 && iLin !== -1)
  assert.ok(Math.abs(iFire - iLin) < 900, "Fire/Linear not adjacent")
  assert.ok(!src.includes("(restarts engine)"))
  assert.ok(src.includes('description: "Fixed-rate drop"'))
})

test("input gain box is half width like other fields", () => {
  const i = src.indexOf('text: "Input gain"')
  assert.ok(i !== -1)
  const window = src.slice(Math.max(0, i - 1200), i)
  assert.ok(window.includes("width: (parent.width - Style.space(14)) / 2"),
    "gain box is not half-width")
})

test("bar color toggle, tones and swatches stay wired", () => {
  assert.ok(src.includes('text: "Custom colors"'))
  assert.ok(src.includes('text: "Custom tones"'))
  assert.ok(src.includes("id: presetRow"))
  assert.ok(src.includes("writeVizOptions3"))
  assert.ok(src.includes("Tap a preset or type hex"))
})

test("no GPU renderer toggle (removed)", () => {
  assert.ok(!src.includes("GPU renderer"))
})

test("clipped stage has top margins in both views", () => {
  const margins = (src.match(/Item \{ width: parent\.width; height: Style\.space\(8\) \}/g) || []).length
  assert.ok(margins >= 2, `expected 2+ clip margins, got ${margins}`)
})

test("Mono sits next to input gain, no standalone toggle", () => {
  const iGain = src.indexOf('text: "Input gain"')
  const iMono = src.indexOf('label: "Mono (mini only)"')
  assert.ok(iGain !== -1 && iMono !== -1)
  assert.ok(Math.abs(iGain - iMono) < 2500, "Mono not next to gain")
  assert.equal((src.match(/label: "Mono \(mini only\)"/g) || []).length, 1)
})

test("Custom colors is a plain switch inside the color box", () => {
  assert.ok(src.includes("id: customSwitch"))
  assert.ok(src.includes("no Toggle box"))
  // exactly one Custom colors label, no Toggle wrapper carrying it
  assert.equal((src.match(/text: "Custom colors"/g) || []).length, 1)
})
