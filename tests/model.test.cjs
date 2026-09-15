// Model.js tests — run: node --test tests/model.test.cjs
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
  assert.equal(d.artwork, false) // v8.0.3: backdrop off for fresh installs
  assert.equal(d.mono, false)
  assert.equal(d.dots, true)
  assert.equal(d.minBarHeight, false)
  // v8.0.3 first-install defaults
  assert.equal(d.gap, 1)
  assert.equal(d.peaks, true)
  assert.equal(d.peakFalloff, 0.1)
  assert.equal(d.reflect, true)
  assert.equal(d.linearFall, true)
  assert.equal(d.stacks, false)
  assert.equal(d.spikes, false)
  assert.equal(d.fire, false)
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

test("themeAccent snapshot parses with fallback", () => {
  const d = Model.readConfigFromText("[desktop]\ntheme_accent = \"#38bdf8\"\n")
  assert.equal(d.themeAccent, "#38bdf8")
  const d2 = Model.readConfigFromText("[desktop]\ntheme_accent = \"blue\"\n")
  assert.equal(d2.themeAccent, "#f59e0b")
  assert.equal(Model.defaultConfig().themeAccent, "#f59e0b")
})

test("legacy splits migrates to canonical stacks", () => {
  const d = Model.readConfigFromText("[desktop]\nsplits = true\n")
  assert.equal(d.stacks, true)
  const d2 = Model.readConfigFromText("[desktop]\nstacks = true\n")
  assert.equal(d2.stacks, true)
  const d3 = Model.readConfigFromText("[desktop]\nstacks = false\n")
  assert.equal(d3.stacks, false)
  assert.equal(Model.defaultConfig().stacks, false)
})

// Every panel option: write the key the panel writes, parse it back.
// Catches writer/reader key drift (e.g. panel writes X, Model reads Y).
test("each panel option round-trips through write + parse", () => {
  const cases = [
    // [section, key, written value, parsed prop, expected]
    ["desktop", "peaks", false, "peaks", false],
    ["desktop", "peak_falloff", 0.1, "peakFalloff", 0.1],
    ["desktop", "reflect", true, "reflect", true],
    ["desktop", "artwork", false, "artwork", false],
    ["desktop", "bar_color_custom", true, "barColorCustom", true],
    ["desktop", "bar_color_from", "#112233", "barColorFrom", "#112233"],
    ["desktop", "bar_color_to", "#aabbcc", "barColorTo", "#aabbcc"],
    ["desktop", "spikes", true, "spikes", true],
    ["desktop", "stacks", true, "stacks", true],
    ["desktop", "fire", true, "fire", true],
    ["desktop", "scope", true, "scope", true],
    ["desktop", "scope_thickness", 3.5, "scopeThickness", 3.5],
    ["desktop", "gpu", false, "gpu", false],
    ["desktop", "linear_fall", true, "linearFall", true],
    ["desktop", "mono", true, "mono", true],
    ["desktop", "dots", false, "dots", false],
    ["desktop", "theme_bottom", "#111111", "themeBottom", "#111111"],
    ["desktop", "theme_top", "#222222", "themeTop", "#222222"],
    ["desktop", "theme_accent", "#333333", "themeAccent", "#333333"],
    ["mini", "gap", 1, "gap", 1],
    ["audio", "sensitivity", 1.2, "sensitivity", 1.2],
    ["audio", "bands", 64, "bands", 64],
  ]
  for (const [section, key, value, prop, expected] of cases) {
    const txt = Model.writeConfigKey("", section, key, value)
    const d = Model.readConfigFromText(txt)
    assert.equal(d[prop], expected, `${section}.${key} round-trip`)
  }
})

test("toggle flip-flop: on then off parses both ways", () => {
  for (const key of ["peaks", "reflect", "artwork", "spikes", "stacks", "fire", "mono", "gpu", "linear_fall", "bar_color_custom"]) {
    let txt = Model.writeConfigKey("", "desktop", key, true)
    assert.equal(Model.readConfigFromText(txt)[key === "linear_fall" ? "linearFall" : key === "bar_color_custom" ? "barColorCustom" : key], true, `${key} on`)
    txt = Model.writeConfigKey(txt, "desktop", key, false)
    assert.equal(Model.readConfigFromText(txt)[key === "linear_fall" ? "linearFall" : key === "bar_color_custom" ? "barColorCustom" : key], false, `${key} off`)
  }
})
