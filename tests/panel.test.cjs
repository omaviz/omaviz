// Panel.qml UI-contract tests — run: node --test tests/panel.test.cjs
// Static source checks for the redesign-v4 settings-panel UX rules:
//   * grouped by intent (LOOK / COLOR / MOTION), one concept per control
//   * chips for exclusive choices (geometry, colour mode, gradient direction)
//   * Flame is a COLOUR MODE, not a geometry-coupled toggle
//   * Advanced is collapsed, not a separate slide-out view
// qmllint only checks syntax, so these guards catch structural regressions.
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
const count = (re) => (src.match(re) || []).length

test("panel is grouped by intent with the expected section headers", () => {
  for (const h of ["VISUALIZATIONS", "PREVIEW", "LOOK", "COLOR", "MOTION", "OSCILLOSCOPE"]) {
    assert.ok(src.includes(`PanelSectionHeader { text: "${h}" }`), `missing ${h} group`)
  }
})

test("all toggle helper texts are single short liners", () => {
  const ds = descriptions()
  assert.ok(ds.length >= 6, `expected 6+ descriptions, got ${ds.length}`)
  for (const d of ds) {
    assert.ok(!d.includes("\\n"), `multiline helper: ${d}`)
    assert.ok(d.length <= 45, `helper too long (${d.length}): ${d}`)
  }
})

test("sliders live in shell-styled boxes", () => {
  assert.ok(count(/BorderSurface \{/g) >= 4, `expected 4+ BorderSurface boxes, got ${count(/BorderSurface \{/g)}`)
  assert.ok(src.includes('borderSpec: Border.controlSpec("normal"'))
  assert.ok(src.includes("Style.controlFill(false, false,"))
})

test("only VizCard + preview use the flat popup fill", () => {
  assert.equal(count(/Color\.popups\.background/g), 2)
})

test("geometry is ONE exclusive choice via chips (Bars / Spikes / Stacks)", () => {
  for (const g of ["Bars", "Spikes", "Stacks"]) {
    assert.ok(src.includes(`chipLabel: "${g}"`), `missing ${g} chip`)
  }
  // Bars clears both flags in a single atomic write; Spikes/Stacks are exclusive.
  assert.ok(src.includes('writeVizOptions3("spikes", false, "stacks", false)'))
  assert.ok(src.includes('writeVizOptions3("spikes", true, "stacks", false)'))
  assert.ok(src.includes('writeVizOptions3("stacks", true, "spikes", false)'))
})

test("colour mode is ONE exclusive choice via chips (Theme / Custom / Flame)", () => {
  for (const c of ["Theme", "Custom", "Flame"]) {
    assert.ok(src.includes(`chipLabel: "${c}"`), `missing ${c} chip`)
  }
  // Flame is a colour mode: it sets fire=true and does NOT touch geometry.
  const flame = src.slice(src.indexOf('chipLabel: "Flame"'), src.indexOf('chipLabel: "Flame"') + 260)
  assert.ok(flame.includes('writeVizOption("fire", true)'), "Flame must set fire")
  assert.ok(!flame.includes('"spikes"') && !flame.includes('"stacks"'), "Flame must not touch geometry")
})

test("Flame is no longer a standalone geometry-coupled toggle", () => {
  // The old Advanced view had a Fire Toggle that also flipped Spikes.
  assert.ok(!src.includes('label: "Fire"'), "Fire must be a colour-mode chip, not a toggle")
})

test("gradient direction is a chip pair writing bar_gradient_dir", () => {
  assert.ok(src.includes('chipLabel: "Vertical"'))
  assert.ok(src.includes('chipLabel: "Horizontal"'))
  assert.ok(src.includes('writeVizOption("bar_gradient_dir", "vertical")'))
  assert.ok(src.includes('writeVizOption("bar_gradient_dir", "horizontal")'))
})

test("preset row keeps 8 gradients + a Fire swatch", () => {
  assert.ok(src.includes("id: presetRow"))
  // 9 swatches share the row: model array (8) + the flame swatch.
  assert.ok(src.includes('gradient: Gradient'))
  assert.ok(src.includes('"#b91c1c"'), "fire swatch gradient must be present")
  assert.ok(src.includes("writeVizOptions3"), "preset click must use the atomic multi-key writer")
})

test("Advanced is collapsed, not a separate slide-out view", () => {
  assert.ok(src.includes('text: root.showAdvanced ? "Hide" : "Show"'))
  assert.ok(src.includes("onClicked: root.showAdvanced = !root.showAdvanced"))
  assert.ok(src.includes("visible: root.showAdvanced"))
  // the old slide-out stage is gone
  assert.ok(!src.includes("id: optStage"))
  assert.ok(!src.includes('text: "Advanced »"'))
})

test("one concept per control: no duplicated concepts in the panel", () => {
  // Response (was "Input gain") owns reactivity; there is no second slider.
  assert.ok(src.includes('text: "Response"'))
  assert.ok(!src.includes('text: "Input gain"'))
  assert.ok(!src.includes('text: "Sensitivity"'))
  // Custom colors is now the "Custom" chip, not a bespoke switch.
  assert.ok(!src.includes("id: customSwitch"))
  assert.ok(!src.includes('text: "Custom colors"'))
  // exactly one Mono toggle
  assert.equal(count(/label: "Mono \(mini only\)"/g), 1)
  assert.ok(!src.includes("(restarts engine)"))
  assert.ok(!src.includes('text: "BARS"'))
})

test("no GPU renderer labeled toggle text left over", () => {
  assert.ok(!src.includes("GPU renderer"))
})
