// ModelStore.js tests — run: node --test tests/modelstore.test.cjs
//
// Covers the config model AND the reactive store:
//   * defaults + the DEFAULT-TRUE invariant (the "theme palette ignored" class
//     of bug: a true-by-default boolean must stay true when its key is absent)
//   * TOML read/write round-trips (writer/reader key drift)
//   * the store funnel: get/set/onChanged/loadFromTOML/toTOML/validate
"use strict"
const fs = require("fs")
const path = require("path")
const { test } = require("node:test")
const assert = require("node:assert/strict")

function loadModule(file) {
  const src = fs.readFileSync(path.join(__dirname, "..", file), "utf8")
  // .pragma library is QML-only — strip it so node can parse the file.
  const js = src.replace(/^\.pragma library\s*/, "")
  // NOTE (security): new Function loads a LOCAL repo file in a test harness —
  // no untrusted/interpolated input, so no injection risk.
  const module = { exports: {} }
  new Function("module", "exports", js)(module, module.exports)
  return module.exports
}
const Store = loadModule("ModelStore.js")

// ---------------------------------------------------------------- defaults
test("defaultConfig carries the redesign keys with theme defaults", () => {
  const d = Store.defaultConfig()
  assert.equal(d.barColorCustom, false)
  assert.equal(d.barColorFrom, "#e68e0d")
  assert.equal(d.barColorTo, "#f59e0b")
  assert.equal(d.barGradientDir, "vertical")
  assert.equal(d.artMode, undefined, "artMode is no longer exported")
  assert.equal(d.artwork, false) // backdrop off for fresh installs
  assert.equal(d.mono, false)
  assert.equal(d.dots, true)
  assert.equal(d.minBarHeight, undefined, "minBarHeight is no longer exported")
  assert.equal(d.gap, 1)
  assert.equal(d.peaks, true)
  assert.equal(d.peakFalloff, 0.1)
  assert.equal(d.peakSustainMs, 100)
  assert.equal(d.reflect, true)
  assert.equal(d.linearFall, true)
  assert.equal(d.colorSync, true)
  assert.equal(d.stacks, false)
  assert.equal(d.spikes, false)
  assert.equal(d.fire, false)
})

// REGRESSION GUARD for the "theme palette ignored" bug. Every boolean whose
// default is true must survive a config that simply omits the key, AND every
// key must match defaultConfig() when absent. If this fails, some reader uses
// `=== "true"` (or `!== "false"`) where it must match the declared default.
test("a minimal config leaves EVERY unspecified key at its default", () => {
  // A file that names one unrelated key: everything else must be untouched.
  const d = Store.readConfigFromText("[desktop]\nscope = false\n")
  const def = Store.defaultConfig()
  for (const k of Object.keys(def)) {
    if (k === "scope") continue
    assert.deepEqual(d[k], def[k], `${k}: absent key must equal defaultConfig()`)
  }
  assert.equal(d.scope, false)
})

test("true-by-default booleans survive a config that omits their key", () => {
  const d = Store.readConfigFromText("[desktop]\nscope = false\n")
  assert.equal(d.colorSync, true, "colorSync must default ON (theme palette)")
  assert.equal(d.linearFall, true, "linearFall must default ON")
  assert.equal(d.reflect, true, "reflect must default ON")
  assert.equal(d.dots, true, "dots must default ON")
  assert.equal(d.artwork, false, "artwork defaults OFF by design")
  assert.equal(d.peaks, true, "peaks must default ON")
  assert.equal(d.enabled, true, "enabled must default ON")
  // And the explicit false must still win.
  const off = Store.readConfigFromText(
    "[desktop]\nlinear_fall = false\nreflect = false\n[mini]\ncolor_sync = false\n"
  )
  assert.equal(off.colorSync, false)
  assert.equal(off.linearFall, false)
  assert.equal(off.reflect, false)
})

test("defaultConfig and readConfigFromText agree on every key for an empty file", () => {
  const d = Store.defaultConfig()
  const p = Store.readConfigFromText("")
  for (const k of Object.keys(d)) {
    assert.deepEqual(p[k], d[k], `empty file: ${k} must match default`)
  }
})

// ---------------------------------------------------------------- helpers
test("isHexColor accepts only strict #rrggbb", () => {
  assert.equal(Store.isHexColor("#e68e0d"), true)
  assert.equal(Store.isHexColor("#FFFFFF"), true)
  assert.equal(Store.isHexColor("e68e0d"), false)
  assert.equal(Store.isHexColor("#fff"), false)
  assert.equal(Store.isHexColor("#gggggg"), false)
  assert.equal(Store.isHexColor(""), false)
  assert.equal(Store.isHexColor(null), false)
  assert.equal(Store.isHexColor("#e68e0d "), false)
})

test("bar color keys parse and invalid tones fall back to theme pair", () => {
  const toml = "[desktop]\nbar_color_custom = true\nbar_color_from = \"#112233\"\nbar_color_to = \"#aabbcc\"\n"
  const d = Store.readConfigFromText(toml)
  assert.equal(d.barColorCustom, true)
  assert.equal(d.barColorFrom, "#112233")
  assert.equal(d.barColorTo, "#aabbcc")

  const bad = "[desktop]\nbar_color_custom = true\nbar_color_from = \"red\"\nbar_color_to = \"#12345\"\n"
  const d2 = Store.readConfigFromText(bad)
  assert.equal(d2.barColorCustom, true) // flag stays; tones sanitize
  assert.equal(d2.barColorFrom, "#e68e0d")
  assert.equal(d2.barColorTo, "#f59e0b")
})

test("bar gradient direction parses, defaults to vertical, rejects junk", () => {
  const d = Store.readConfigFromText('[desktop]\nbar_gradient_dir = "horizontal"\n')
  assert.equal(d.barGradientDir, "horizontal")
  const def = Store.readConfigFromText("[desktop]\n")
  assert.equal(def.barGradientDir, "vertical")
  const bad = Store.readConfigFromText('[desktop]\nbar_gradient_dir = "diagonal"\n')
  assert.equal(bad.barGradientDir, "vertical")
})

test("artwork_mode retires to spectrum + backdrop on", () => {
  const d = Store.readConfigFromText("[desktop]\nartwork_mode = true\n")
  assert.equal(d.scope, false)
  assert.equal(d.artwork, true)

  const d2 = Store.readConfigFromText("[desktop]\nimmersive = true\nartwork = false\n")
  assert.equal(d2.artwork, false)
})

test("plain spectrum config is untouched by the migration", () => {
  const d = Store.readConfigFromText("[desktop]\nscope = false\nartwork = false\n")
  assert.equal(d.scope, false)
  assert.equal(d.artwork, false)
})

test("removed-from-UI keys stay readable in code", () => {
  const toml = "[desktop]\ndots = false\nmono = true\n"
  const d = Store.readConfigFromText(toml)
  assert.equal(d.dots, false)
  assert.equal(d.mono, true)
})

test("sensitivity reads from [audio] and is clamped to a sane range", () => {
  assert.equal(Store.readConfigFromText("[audio]\nsensitivity = 1.5\n").sensitivity, 1.5)
  assert.equal(Store.readConfigFromText("[audio]\nsensitivity = 99\n").sensitivity, 4)
  assert.equal(Store.readConfigFromText("[audio]\nsensitivity = 0.001\n").sensitivity, 1.0)
  assert.equal(Store.readConfigFromText("[audio]\nsensitivity = abc\n").sensitivity, 1.0)
})

test("peakSustainMs parses, defaults to 100 and clamps to 0..1000", () => {
  assert.equal(Store.readConfigFromText("[desktop]\npeak_sustain_ms = 250\n").peakSustainMs, 250)
  assert.equal(Store.readConfigFromText("[desktop]\n").peakSustainMs, 100)
  assert.equal(Store.readConfigFromText("[desktop]\npeak_sustain_ms = -5\n").peakSustainMs, 0)
  assert.equal(Store.readConfigFromText("[desktop]\npeak_sustain_ms = 9999\n").peakSustainMs, 1000)
})

test("themeAccent snapshot parses with fallback", () => {
  assert.equal(Store.readConfigFromText("[desktop]\ntheme_accent = \"#38bdf8\"\n").themeAccent, "#38bdf8")
  assert.equal(Store.readConfigFromText("[desktop]\ntheme_accent = \"blue\"\n").themeAccent, "#f59e0b")
  assert.equal(Store.defaultConfig().themeAccent, "#f59e0b")
})

test("legacy splits migrates to canonical stacks", () => {
  assert.equal(Store.readConfigFromText("[desktop]\nsplits = true\n").stacks, true)
  assert.equal(Store.readConfigFromText("[desktop]\nstacks = true\n").stacks, true)
  assert.equal(Store.readConfigFromText("[desktop]\nstacks = false\n").stacks, false)
})

// ---------------------------------------------------------------- round-trips
test("writeConfigKey round-trips the new keys", () => {
  let txt = ""
  txt = Store.writeConfigKey(txt, "desktop", "bar_color_custom", true)
  txt = Store.writeConfigKey(txt, "desktop", "bar_color_from", "#112233")
  txt = Store.writeConfigKey(txt, "desktop", "bar_color_to", "#aabbcc")
  txt = Store.writeConfigKey(txt, "audio", "sensitivity", 1.5)
  const d = Store.readConfigFromText(txt)
  assert.equal(d.barColorCustom, true)
  assert.equal(d.barColorFrom, "#112233")
  assert.equal(d.barColorTo, "#aabbcc")
  assert.equal(d.sensitivity, 1.5)
})

test("each panel option round-trips through write + parse", () => {
  const cases = [
    ["desktop", "peaks", false, "peaks", false],
    ["desktop", "peak_falloff", 0.1, "peakFalloff", 0.1],
    ["desktop", "peak_sustain_ms", 150, "peakSustainMs", 150],
    ["desktop", "reflect", true, "reflect", true],
    ["desktop", "artwork", false, "artwork", false],
    ["desktop", "bar_color_custom", true, "barColorCustom", true],
    ["desktop", "bar_color_from", "#112233", "barColorFrom", "#112233"],
    ["desktop", "bar_color_to", "#aabbcc", "barColorTo", "#aabbcc"],
    ["desktop", "bar_gradient_dir", "horizontal", "barGradientDir", "horizontal"],
    ["desktop", "spikes", true, "spikes", true],
    ["desktop", "stacks", true, "stacks", true],
    ["desktop", "fire", true, "fire", true],
    ["desktop", "scope", true, "scope", true],
    ["desktop", "scope_thickness", 3.5, "scopeThickness", 3.5],
    ["desktop", "linear_fall", true, "linearFall", true],
    ["desktop", "mono", true, "mono", true],
    ["desktop", "dots", false, "dots", false],
    ["desktop", "theme_bottom", "#111111", "themeBottom", "#111111"],
    ["desktop", "theme_top", "#222222", "themeTop", "#222222"],
    ["desktop", "theme_accent", "#333333", "themeAccent", "#333333"],
    ["mini", "gap", 1, "gap", 1],
    ["mini", "color_sync", true, "colorSync", true],
    ["audio", "sensitivity", 1.2, "sensitivity", 1.2],
    ["audio", "bands", 64, "bands", 64],
  ]
  for (const [section, key, value, prop, expected] of cases) {
    const txt = Store.writeConfigKey("", section, key, value)
    const d = Store.readConfigFromText(txt)
    assert.equal(d[prop], expected, `${section}.${key} round-trip`)
  }
})

test("toggle flip-flop: on then off parses both ways", () => {
  const map = { linear_fall: "linearFall", bar_color_custom: "barColorCustom", color_sync: "colorSync" }
  for (const key of ["peaks", "reflect", "artwork", "spikes", "stacks", "fire", "mono", "linear_fall", "bar_color_custom", "color_sync"]) {
    let txt = Store.writeConfigKey("", key === "color_sync" ? "mini" : "desktop", key, true)
    assert.equal(Store.readConfigFromText(txt)[map[key] || key], true, `${key} on`)
    txt = Store.writeConfigKey(txt, key === "color_sync" ? "mini" : "desktop", key, false)
    assert.equal(Store.readConfigFromText(txt)[map[key] || key], false, `${key} off`)
  }
})

// ---------------------------------------------------------------- toTOML
test("toTOML emits a complete, re-parseable document with all defaults", () => {
  const txt = Store.toTOML(Store.defaultConfig())
  assert.match(txt, /\[audio\]/)
  assert.match(txt, /\[mini\]/)
  assert.match(txt, /\[desktop\]/)
  assert.match(txt, /color_sync = true/, "fresh install must start with theme sync ON")
  assert.match(txt, /peak_sustain_ms = 100/)
  const d = Store.readConfigFromText(txt)
  const def = Store.defaultConfig()
  for (const k of Object.keys(def)) {
    if (k === "desktopActive" || k === "desktopHeartbeat") continue // runtime keys omitted
    assert.deepEqual(d[k], def[k], `toTOML round-trip: ${k}`)
  }
})

test("a fresh writeConfigKey('') bootstraps a theme-synced config, not color_sync=false", () => {
  const txt = Store.writeConfigKey("", "desktop", "peaks", true)
  const d = Store.readConfigFromText(txt)
  assert.equal(d.colorSync, true, "bootstrap must not disable theme sync")
  assert.equal(d.peaks, true)
})

test("sourceLabel maps backend names and passes unknown through", () => {
  assert.equal(Store.sourceLabel("pipewire"), "PipeWire")
  assert.equal(Store.sourceLabel("gen"), "Generator")
  assert.equal(Store.sourceLabel("weird"), "weird")
  assert.equal(Store.sourceLabel(""), "Unknown")
})

// SECURITY REGRESSION: an unescaped interior double-quote in a written value
// produced invalid TOML, and the whole config file then mis-parsed.
test("writeConfigKey escapes an interior double-quote; readTomlValue round-trips it", () => {
  const raw = 'a"b'
  const text = Store.writeConfigKey("", "desktop", "weird", raw)
  const line = text.split("\n").find(l => l.startsWith("weird"))
  assert.ok(line.includes('\\"'), `interior quote must be escaped: ${line}`)
  assert.equal(Store.readTomlValue(text, "desktop", "weird"), raw)
})

test("writeConfigKey keeps ordinary values unchanged in shape", () => {
  const text = Store.writeConfigKey("", "desktop", "fire", true)
  assert.ok(text.includes("fire = true"), text)
  const text2 = Store.writeConfigKey("", "mini", "gap", 1)
  assert.ok(text2.includes("gap = 1"), text2)
  const text3 = Store.writeConfigKey("", "desktop", "bar_color_from", "#e68e0d")
  assert.ok(text3.includes('bar_color_from = "#e68e0d"'), text3)
})

test("explicit settings override legacy aliases", () => {
  const text = '[desktop]\nsplits = true\nartwork_mode = true\nimmersive = true\n';
  let edited = Store.writeConfigKey(text, 'desktop', 'stacks', false);
  edited = Store.writeConfigKey(edited, 'desktop', 'artwork', false);
  const config = Store.readConfigFromText(edited);
  assert.equal(config.stacks, false);
  assert.equal(config.artwork, false);
  assert.equal(Store.readConfigFromText(text).stacks, true);
  assert.equal(Store.readConfigFromText(text).artwork, true);
});

test("flame tones persist independently from custom presets", () => {
  let text = Store.toTOML(Store.defaultConfig());
  text = Store.writeConfigKey(text, 'desktop', 'fire_color_to', '#aabbcc');
  text = Store.writeConfigKey(text, 'desktop', 'bar_color_to', '#112233');
  const config = Store.readConfigFromText(text);
  assert.equal(config.fireColorTo, '#aabbcc');
  assert.equal(config.barColorTo, '#112233');
  assert.equal(Store.readConfigFromText(Store.toTOML(config)).fireColorTo, '#aabbcc');
  assert.equal(Store.readConfigFromText('[desktop]\nfire_color_to = "bad"').fireColorTo, '#fde047');
});

test("TOML comments and escaped strings preserve settings without injecting keys", () => {
  const text = '[desktop] # settings\nfire = false # disabled\nbar_color_to = "#112233" # tip\n';
  assert.equal(Store.readConfigFromText(text).fire, false);
  assert.equal(Store.readConfigFromText(text).barColorTo, '#112233');
  for (const value of ['a\\b', 'a"b', 'line\nbreak', '[desktop]\nfire = true', '"quoted"']) {
    const written = Store.writeConfigKey(text, 'desktop', 'label', value);
    assert.equal(Store.readTomlValue(written, 'desktop', 'label'), value);
    assert.equal(Store.readConfigFromText(written).fire, false);
  }
  const written = Store.writeConfigKey(text, 'desktop', 'fire', true);
  assert.equal((written.match(/\[desktop\]/g) || []).length, 1);
  assert.equal(Store.readConfigFromText(written).fire, true);
});
