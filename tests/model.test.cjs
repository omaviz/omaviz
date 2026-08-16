// Tests for the omaviz plugin Model.js (shared config/visual logic).
//
// These exercises are the pure-JS functions that back the settings panel and
// bar widget. Model.js is a `.pragma library` QML singleton, so we load it
// under node by stripping the pragma + the `module.exports` guard and
// re-exporting the functions we want to test.
//
// Run:  node tests/model.test.cjs
// (uses node:test / node:assert — no dependencies)

const fs = require('node:fs')
const path = require('node:path')
const Module = require('node:module')
const test = require('node:test').test
const assert = require('node:assert')

function loadModel () {
  const modelPath = path.resolve(__dirname, '..', 'Model.js')
  let src = fs.readFileSync(modelPath, 'utf8')
    .replace(/^\.pragma library\s*$/m, '')
    .replace(/if \(typeof module[\s\S]*$/, '')
  src += `
module.exports = {
  readTomlValue, readTomlFloat, readTomlInt,
  readConfigFromText, defaultConfig, writeConfigKey,
  parseVisualToml, discoverVisualsFromText, visualParamsFromText,
  visualConfigValues, readAudioFromText, parseSpectrumLine,
  isDesktopActiveFromText, spectrumData, listVisualFiles
}`
  const m = new Module('omaviz-model', null)
  m.filename = modelPath
  m.paths = Module._nodeModulePaths(path.dirname(modelPath))
  m._compile(src, modelPath)
  return m.exports
}

const M = loadModel()

// ---- Fixtures: the real visuals/*.toml content (kept in sync with repo) ----
const EQUALIZER_TOML = `
label = "Bars"
description = "Classic vertical bar spectrograph."

[[params]]
name = "bar_count"
label = "Bar count"
default = 32
min = 8
max = 64
type = "int"

[[params]]
name = "colour_scheme"
label = "Colour scheme"
default = 0
min = 0
max = 2
type = "int"

[[params]]
name = "peak_fall"
label = "Peak fall speed"
default = 0.5
min = 0
max = 1
type = "float"
`

const FIRE_TOML = `
label = "Fire"
description = "Winamp-style fluid flame (a style of the Bars visual)."

[[params]]
name = "borderless"
label = "Borderless (merged flame)"
boolean = true
default = 1.0

[[params]]
name = "smoothing"
label = "Liquid edge"
default = 0.5
min = 0
max = 1
type = "float"

[[params]]
name = "bg_fade"
label = "Background glow with music"
default = 0.6
min = 0
max = 1
type = "float"

[[params]]
name = "intensity"
label = "Flame brightness"
default = 1.0
min = 0.2
max = 2.0
type = "float"

[[params]]
name = "peak_fall"
label = "Peak-hold fall speed"
default = 0.08
min = 0.01
max = 0.5
type = "float"
`

const WAVE_TOML = `
label = "Wave"
description = "Smooth mirrored sine ribbon (string-like)."

[[params]]
name = "amplitude"
label = "Amplitude"
default = 0.7
min = 0.1
max = 1.5
type = "float"

[[params]]
name = "frequency"
label = "Frequency"
default = 1.0
min = 0.2
max = 3.0
type = "float"

[[params]]
name = "brightness"
label = "Brightness"
default = 0.6
min = 0.1
max = 1.0
type = "float"

[[params]]
name = "peak_fall"
label = "Peak fall speed"
default = 0.3
min = 0
max = 1
type = "float"
`

// ===========================================================================
// TOML read helpers
// ===========================================================================
test('readTomlValue: reads a value and strips quotes', () => {
  const t = '[audio]\nsensitivity = 1.0\nbands = 32\n\n[mini]\nvisual = "equalizer"\n'
  assert.strictEqual(M.readTomlValue(t, 'audio', 'sensitivity'), '1.0')
  assert.strictEqual(M.readTomlValue(t, 'mini', 'visual'), 'equalizer')
})

test('readTomlValue: null when missing or wrong section', () => {
  const t = '[audio]\nbands = 32\n'
  assert.strictEqual(M.readTomlValue(t, 'mini', 'visual'), null)
  assert.strictEqual(M.readTomlValue(t, 'audio', 'nope'), null)
  assert.strictEqual(M.readTomlValue('', 'audio', 'bands'), null)
})

test('readTomlFloat / readTomlInt parse correctly', () => {
  const t = '[audio]\nsensitivity = 1.5\nbands = 32\n'
  assert.strictEqual(M.readTomlFloat(t, 'audio', 'sensitivity'), 1.5)
  assert.strictEqual(M.readTomlInt(t, 'audio', 'bands'), 32)
  assert.strictEqual(M.readTomlInt(t, 'audio', 'missing'), null)
})

// ===========================================================================
// Config read
// ===========================================================================
test('defaultConfig: expected defaults', () => {
  const d = M.defaultConfig()
  assert.strictEqual(d.visualMini, 'equalizer')
  assert.strictEqual(d.visualDesktop, 'equalizer')
  assert.strictEqual(d.visualFull, 'wave')
  assert.strictEqual(d.style, 'classic')
  assert.strictEqual(d.styleDesktop, 'classic')
  assert.strictEqual(d.desktopActive, false)
  assert.strictEqual(d.colorSync, false)
  assert.strictEqual(d.bands, 32)
})

test('readConfigFromText: parses all fields incl. style / desktopActive / color_sync', () => {
  const t = `
[audio]
sensitivity = 2.0
smoothing = 0.3
bands = 48

[mini]
visual = "wave"
style = "fire"
color_sync = true

[desktop]
visual = "equalizer"
style = "fire"
active = "true"

[full]
visual = "wave"
`
  const d = M.readConfigFromText(t)
  assert.strictEqual(d.sensitivity, 2.0)
  assert.strictEqual(d.bands, 48)
  assert.strictEqual(d.visualMini, 'wave')
  assert.strictEqual(d.visualDesktop, 'equalizer')
  assert.strictEqual(d.style, 'fire')             // read from [mini]
  assert.strictEqual(d.styleDesktop, 'fire')      // read from [desktop]
  assert.strictEqual(d.desktopActive, true)       // pause flag
  assert.strictEqual(d.colorSync, true)
})

test('readConfigFromText: empty text -> defaults (no throw)', () => {
  const d = M.readConfigFromText('')
  assert.deepStrictEqual(d, M.defaultConfig())
})

test('readConfigFromText: missing keys fall back to defaults', () => {
  const d = M.readConfigFromText('[audio]\nbands = 16\n')
  assert.strictEqual(d.bands, 16)              // present
  assert.strictEqual(d.sensitivity, 1.0)       // default
  assert.strictEqual(d.colorSync, false)       // default
})

// ===========================================================================
// writeConfigKey — the config.toml corruption fix
// ===========================================================================
test('writeConfigKey: updates in place when key exists', () => {
  const t = '[desktop]\nactive = "false"\n'
  const out = M.writeConfigKey(t, 'desktop', 'active', 'true')
  assert.strictEqual(M.readTomlValue(out, 'desktop', 'active'), 'true')
  // exactly one [desktop] header
  assert.strictEqual((out.match(/\[desktop\]/g) || []).length, 1)
})

test('writeConfigKey: SAME KEY TWICE does not duplicate (regression for corruption bug)', () => {
  let t = '[desktop]\nactive = "false"\n'
  t = M.writeConfigKey(t, 'desktop', 'active', 'true')
  t = M.writeConfigKey(t, 'desktop', 'active', 'false')
  // Only one [desktop] header and one active= line
  assert.strictEqual((t.match(/\[desktop\]/g) || []).length, 1)
  assert.strictEqual((t.match(/active\s*=/g) || []).length, 1)
  assert.strictEqual(M.readTomlValue(t, 'desktop', 'active'), 'false')
})

test('writeConfigKey: inserts key after header when missing in section', () => {
  const t = '[mini]\nvisual = "equalizer"\n'
  const out = M.writeConfigKey(t, 'mini', 'style', 'fire')
  assert.strictEqual(M.readTomlValue(out, 'mini', 'style'), 'fire')
  assert.strictEqual((out.match(/\[mini\]/g) || []).length, 1)
})

test('writeConfigKey: appends missing section', () => {
  const t = '[audio]\nbands = 32\n'
  const out = M.writeConfigKey(t, 'full', 'visual', 'wave')
  assert.strictEqual(M.readTomlValue(out, 'full', 'visual'), 'wave')
  assert.strictEqual((out.match(/\[full\]/g) || []).length, 1)
})

test('writeConfigKey: quotes string values for visual/active keys', () => {
  const out = M.writeConfigKey('', 'mini', 'visual', 'wave')
  assert.ok(out.includes('visual = "wave"'), 'string value should be quoted')
})

test('writeConfigKey: writes to nested [visual.<name>] and is idempotent', () => {
  let t = '[mini]\nvisual = "equalizer"\n'
  t = M.writeConfigKey(t, 'visual.equalizer', 'bar_count', 48)
  t = M.writeConfigKey(t, /* noop reuse */ 0) // placeholder to keep shape
  // re-write same -> still single header + single value
  t = M.writeConfigKey(t, 'visual.equalizer', 'bar_count', 48)
  assert.strictEqual((t.match(/\[visual\.equalizer\]/g) || []).length, 1)
  assert.strictEqual((t.match(/bar_count\s*=/g) || []).length, 1)
  assert.strictEqual(M.readTomlValue(t, 'visual.equalizer', 'bar_count'), '48')
})

test('writeConfigKey: writing two different visual sections keeps headers distinct', () => {
  let t = '[mini]\nvisual = "equalizer"\n'
  t = M.writeConfigKey(t, 'visual.equalizer', 'bar_count', 48)
  t = M.writeConfigKey(t, 'visual.fire', 'intensity', 1.5)
  assert.strictEqual((t.match(/\[visual\.equalizer\]/g) || []).length, 1)
  assert.strictEqual((t.match(/\[visual\.fire\]/g) || []).length, 1)
  assert.strictEqual(M.readTomlValue(t, 'visual.fire', 'intensity'), '1.5')
})

// ===========================================================================
// parseVisualToml — the #2 label-parsing fix
// ===========================================================================
test('parseVisualToml: equalizer params have NON-null labels', () => {
  const v = M.parseVisualToml(EQUALIZER_TOML, 'equalizer')
  assert.strictEqual(v.label, 'Bars')
  assert.strictEqual(v.params.length, 3)
  const labels = v.params.map(p => p.label)
  assert.deepStrictEqual(labels, ['Bar count', 'Colour scheme', 'Peak fall speed'])
  // every param must have a real label (the old bug produced null)
  for (const p of v.params) {
    assert.ok(p.label && p.label.length > 0, `param ${p.name} missing label`)
  }
})

test('parseVisualToml: fire params have NON-null labels incl. boolean flag', () => {
  const v = M.parseVisualToml(FIRE_TOML, 'fire')
  assert.strictEqual(v.label, 'Fire')
  assert.strictEqual(v.params.length, 5)
  const labels = v.params.map(p => p.label)
  assert.ok(labels.includes('Borderless (merged flame)'))
  assert.ok(labels.includes('Flame brightness'))
  const borderless = v.params.find(p => p.name === 'borderless')
  assert.strictEqual(borderless.boolean, true)
})

test('parseVisualToml: wave params have labels', () => {
  const v = M.parseVisualToml(WAVE_TOML, 'wave')
  assert.strictEqual(v.label, 'Wave')
  assert.strictEqual(v.params.length, 4)
  const labels = v.params.map(p => p.label)
  assert.deepStrictEqual(labels, ['Amplitude', 'Frequency', 'Brightness', 'Peak fall speed'])
})

test('parseVisualToml: numeric fields parsed as numbers', () => {
  const v = M.parseVisualToml(EQUALIZER_TOML, 'equalizer')
  const bc = v.params.find(p => p.name === 'bar_count')
  assert.strictEqual(bc.type, 'int')
  assert.strictEqual(bc.default, 32)
  assert.strictEqual(bc.min, 8)
  assert.strictEqual(bc.max, 64)
})

// ===========================================================================
// visualParamsFromText — source tagging
// ===========================================================================
test('visualParamsFromText: tags each param with its source visual', () => {
  const eq = M.visualParamsFromText(EQUALIZER_TOML, 'equalizer')
  assert.ok(eq.every(p => p.source === 'equalizer'))
  const fire = M.visualParamsFromText(FIRE_TOML, 'fire')
  assert.ok(fire.every(p => p.source === 'fire'))
})

// ===========================================================================
// visualConfigValues — the #3 save/read fix (reads from config, per source)
// ===========================================================================
test('visualConfigValues: reads saved values from [visual.<source>] in config', () => {
  const config = `
[mini]
visual = "equalizer"

[visual.equalizer]
bar_count = 48
colour_scheme = 2

[visual.fire]
intensity = 1.5
`
  const eqParams = M.visualParamsFromText(EQUALIZER_TOML, 'equalizer')
  const vals = M.visualConfigValues(config, eqParams)
  assert.strictEqual(vals.bar_count, 48)
  assert.strictEqual(vals.colour_scheme, 2)

  const fireParams = M.visualParamsFromText(FIRE_TOML, 'fire')
  const fvals = M.visualConfigValues(config, fireParams)
  assert.strictEqual(fvals.intensity, 1.5)
})

test('visualConfigValues: falls back to param default when key absent', () => {
  const eqParams = M.visualParamsFromText(EQUALIZER_TOML, 'equalizer')
  const vals = M.visualConfigValues('[mini]\nvisual = "equalizer"\n', eqParams)
  assert.strictEqual(vals.bar_count, 32)   // default
  assert.strictEqual(vals.colour_scheme, 0)
})

test('visualConfigValues: boolean param parsed when present', () => {
  const config = '[visual.fire]\nborderless = "true"\n'
  const fireParams = M.visualParamsFromText(FIRE_TOML, 'fire')
  const vals = M.visualConfigValues(config, fireParams)
  assert.strictEqual(vals.borderless, true)
})

// ===========================================================================
// discoverVisualsFromText — label mapping (Bars/Wave/Fire)
// ===========================================================================
test('discoverVisualsFromText: maps file names to friendly labels, sorted', () => {
  const files = [
    { path: '/x/equalizer.toml', text: EQUALIZER_TOML },
    { path: '/x/wave.toml', text: WAVE_TOML },
    { path: '/x/fire.toml', text: FIRE_TOML }
  ]
  const vis = M.discoverVisualsFromText(files)
  const labels = vis.map(v => v.label)
  assert.deepStrictEqual(labels, ['Bars', 'Fire', 'Wave']) // sorted by label
  // fire is present as a visual definition (used for its style knobs)
  assert.ok(vis.find(v => v.label === 'Fire'))
})

// ===========================================================================
// parseSpectrumLine — spectrum bridge JSON
// ===========================================================================
test('parseSpectrumLine: parses bands JSON and updates spectrumData', () => {
  M.parseSpectrumLine(JSON.stringify({ bands: [0.1, 0.5, 0.9], energy: 0.4, beat: 1, silent: false }))
  assert.deepStrictEqual(M.spectrumData.bands, [0.1, 0.5, 0.9])
  assert.strictEqual(M.spectrumData.silent, false)
  assert.strictEqual(M.spectrumData.energy, 0.4)
})

test('parseSpectrumLine: malformed line does not throw', () => {
  assert.doesNotThrow(() => M.parseSpectrumLine('not json at all {{{'))
})

// ===========================================================================
// readAudioFromText
// ===========================================================================
test('readAudioFromText: parses audio block, defaults when empty', () => {
  const a = M.readAudioFromText('[audio]\nsensitivity = 1.2\nsmoothing = 0.4\nbands = 24\n')
  assert.strictEqual(a.sensitivity, 1.2)
  assert.strictEqual(a.bands, 24)
  const def = M.readAudioFromText('')
  assert.deepStrictEqual(def, { sensitivity: 1.0, smoothing: 0.5, bands: 32 })
})

// ===========================================================================
// isDesktopActiveFromText — pause flag
// ===========================================================================
test('isDesktopActiveFromText: true only when active = "true"', () => {
  assert.strictEqual(M.isDesktopActiveFromText('[desktop]\nactive = "true"\n'), true)
  assert.strictEqual(M.isDesktopActiveFromText('[desktop]\nactive = "false"\n'), false)
  assert.strictEqual(M.isDesktopActiveFromText(''), false)
})

// ===========================================================================
// Integration: pause cycle (detach -> freeze, close -> resume)  [#7]
// ===========================================================================
test('pause cycle: detach writes active=true, close writes active=false', () => {
  let cfg = '[desktop]\nvisual = "equalizer"\nstyle = "classic"\nactive = "false"\n'
  // simulate Detach writing desktop.active=true
  cfg = M.writeConfigKey(cfg, 'desktop', 'active', 'true')
  assert.strictEqual(M.readConfigFromText(cfg).desktopActive, true)   // bar.paused = true
  // simulate window close writing desktop.active=false
  cfg = M.writeConfigKey(cfg, 'desktop', 'active', 'false')
  assert.strictEqual(M.readConfigFromText(cfg).desktopActive, false)  // bar.paused = false
  // still exactly one [desktop] header + one active line
  assert.strictEqual((cfg.match(/\[desktop\]/g) || []).length, 1)
  assert.strictEqual((cfg.match(/active\s*=/g) || []).length, 1)
})

// ===========================================================================
// Integration: style selection round-trip (Fire is a style, not a viz) [#5]
// ===========================================================================
test('style round-trip: selectStyle writes both mini and desktop style, knobs combine', () => {
  let cfg = '[mini]\nvisual = "equalizer"\nstyle = "classic"\n[desktop]\nvisual = "equalizer"\nstyle = "classic"\n'
  // selectStyle("Fire") writes style to both sections
  cfg = M.writeConfigKey(cfg, 'mini', 'style', 'fire')
  cfg = M.writeConfigKey(cfg, 'desktop', 'style', 'fire')
  const d = M.readConfigFromText(cfg)
  assert.strictEqual(d.style, 'fire')
  assert.strictEqual(d.styleDesktop, 'fire')

  // When style=fire + Bars, the panel combines Bars knobs + Fire knobs
  const eq = M.visualParamsFromText(EQUALIZER_TOML, 'equalizer')
  const fire = M.visualParamsFromText(FIRE_TOML, 'fire')
  const combined = eq.concat(fire)
  // every combined param reads/writes to its own [visual.<source>] section
  for (const p of combined) {
    assert.ok(p.source === 'equalizer' || p.source === 'fire')
  }
  // edge case: two different visuals both have peak_fall — must not collide
  const eqPk = combined.find(p => p.source === 'equalizer' && p.name === 'peak_fall')
  const firePk = combined.find(p => p.source === 'fire' && p.name === 'peak_fall')
  assert.ok(eqPk && firePk)
  assert.notStrictEqual(eqPk, firePk)
})
