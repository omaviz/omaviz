// Model.js tests — run: node --test plugin/tests/model.test.cjs
// Covers the settings-redesign contract: new bar-color keys, artwork_mode
// retirement/migration, silent-floor inputs, and keys that stay readable
// in code after their UI was removed (dots, mono, min_bar_height).
"use strict"
const fs = require("fs")
const path = require("path")
const { test } = require("node:test")
const assert = require("node:assert/strict")

function loadModel() {
  const src = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8")
  // .pragma library is QML-only — strip it so node can parse the file.
  const js = src.replace(/^\.pragma library\s*/, "")
  // NOTE (security): new Function loads a LOCAL repo file (Model.js) in a
  // test harness — no untrusted/interpolated input, so no injection risk.
  const module = { exports: {} }
  new Function("module", "exports", js)(module, module.exports)
  return module.exports
}
const Model = loadModel()

test("defaultConfig carries the redesign keys with theme defaults", () => {
  const d = Model.defaultConfig()
  assert.equal(d.barColorCustom, false)
  assert.equal(d.barColorFrom, "#e68e0d")
  assert.equal(d.barColorTo, "#f59e0b")
  assert.equal(d.artMode, false)
  assert.equal(d.artwork, true)
  assert.equal(d.mono, false)
  assert.equal(d.dots, true)
  assert.equal(d.minBarHeight, false)
})

test("isHexColor accepts only strict #rrggbb", () => {
  assert.equal(Model.isHexColor("#e68e0d"), true)
  assert.equal(Model.isHexColor("#FFFFFF"), true)
  assert.equal(Model.isHexColor("e68e0d"), false)
  assert.equal(Model.isHexColor("#fff"), false)
  assert.equal(Model.isHexColor("#gggggg"), false)
  assert.equal(Model.isHexColor(""), false)
  assert.equal(Model.isHexColor(null), false)
  assert.equal(Model.isHexColor("#e68e0d "), false)
})

test("bar color keys parse and invalid tones fall back to theme pair", () => {
  const toml = "[desktop]\nbar_color_custom = true\nbar_color_from = \"#112233\"\nbar_color_to = \"#aabbcc\"\n"
  const d = Model.readConfigFromText(toml)
  assert.equal(d.barColorCustom, true)
  assert.equal(d.barColorFrom, "#112233")
  assert.equal(d.barColorTo, "#aabbcc")

  const bad = "[desktop]\nbar_color_custom = true\nbar_color_from = \"red\"\nbar_color_to = \"#12345\"\n"
  const d2 = Model.readConfigFromText(bad)
  assert.equal(d2.barColorCustom, true) // flag stays; tones sanitize
  assert.equal(d2.barColorFrom, "#e68e0d")
  assert.equal(d2.barColorTo, "#f59e0b")
})

test("artwork_mode retires to spectrum + backdrop on", () => {
  const d = Model.readConfigFromText("[desktop]\nartwork_mode = true\n")
  assert.equal(d.artMode, false)
  assert.equal(d.scope, false)
  assert.equal(d.artwork, true)

  // pre-rename key migrates the same way
  const d2 = Model.readConfigFromText("[desktop]\nimmersive = true\nartwork = false\n")
  assert.equal(d2.artMode, false)
  assert.equal(d2.artwork, true)
})

test("plain spectrum config is untouched by the migration", () => {
  const d = Model.readConfigFromText("[desktop]\nscope = false\nartwork = false\n")
  assert.equal(d.artMode, false)
  assert.equal(d.scope, false)
  assert.equal(d.artwork, false)
})

test("removed-from-UI keys stay readable in code", () => {
  const toml = "[desktop]\ndots = false\nmono = true\nmin_bar_height = true\n"
  const d = Model.readConfigFromText(toml)
  assert.equal(d.dots, false)
  assert.equal(d.mono, true)
  assert.equal(d.minBarHeight, true)
})

test("sensitivity reads from [audio] (QML-side, panel writes it back)", () => {
  const d = Model.readConfigFromText("[audio]\nsensitivity = 1.5\n")
  assert.equal(d.sensitivity, 1.5)
})

test("writeConfigKey round-trips the new keys", () => {
  let txt = ""
  txt = Model.writeConfigKey(txt, "desktop", "bar_color_custom", true)
  txt = Model.writeConfigKey(txt, "desktop", "bar_color_from", "#112233")
  txt = Model.writeConfigKey(txt, "desktop", "bar_color_to", "#aabbcc")
  txt = Model.writeConfigKey(txt, "audio", "sensitivity", 1.5)
  const d = Model.readConfigFromText(txt)
  assert.equal(d.barColorCustom, true)
  assert.equal(d.barColorFrom, "#112233")
  assert.equal(d.barColorTo, "#aabbcc")
  assert.equal(d.sensitivity, 1.5)
})
