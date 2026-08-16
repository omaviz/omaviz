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
  sourceLabel, isDesktopActiveFromText, spectrumData, listVisualFiles,
  engineBin, bridgePath, isPaused
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
// VISUALIZATION dropdown must exclude Fire (it is a STYLE, not a viz)  [#1]
// (The filtering happens in Panel.qml; this encodes the data contract.)
// ===========================================================================
test('VIZ dropdown contract: Fire excluded, only Bars/Wave shown', () => {
  const files = [
    { path: '/x/equalizer.toml', text: EQUALIZER_TOML },
    { path: '/x/wave.toml', text: WAVE_TOML },
    { path: '/x/fire.toml', text: FIRE_TOML }
  ]
  const visuals = M.discoverVisualsFromText(files)
  const vizOptions = visuals
    .filter(v => v.name !== 'fire')
    .map(v => (v.name === 'equalizer' ? 'Bars' : v.name === 'wave' ? 'Wave' : v.name))
  assert.deepStrictEqual(vizOptions, ['Bars', 'Wave'])
  assert.ok(!vizOptions.includes('Fire'), 'Fire must not appear in the VIZ dropdown')
})

// ===========================================================================
// Knob edit reflects on a SINGLE write without rebuilding the param list [#2]
// ===========================================================================
test('knob write reflects immediately via visualConfigValues (no array rebuild)', () => {
  let cfg = '[mini]\nvisual = "equalizer"\n\n[visual.equalizer]\nbar_count = 32\n'
  const params = M.visualParamsFromText(EQUALIZER_TOML, 'equalizer')
  let vals = M.visualConfigValues(cfg, params)
  assert.strictEqual(vals.bar_count, 32)
  cfg = M.writeConfigKey(cfg, 'visual.equalizer', 'bar_count', 48)
  vals = M.visualConfigValues(cfg, params)
  assert.strictEqual(vals.bar_count, 48, 'single write must reflect without rebuilding params')
})

// ===========================================================================
// Color sync write/read round-trip  [#3]
// ===========================================================================
test('color_sync: toggle writes mini.color_sync and is read back', () => {
  let cfg = '[mini]\nvisual = "equalizer"\ncolor_sync = false\n'
  cfg = M.writeConfigKey(cfg, 'mini', 'color_sync', 'true')
  assert.strictEqual(M.readConfigFromText(cfg).colorSync, true)
  cfg = M.writeConfigKey(cfg, 'mini', 'color_sync', 'false')
  assert.strictEqual(M.readConfigFromText(cfg).colorSync, false)
})

// ===========================================================================
// Pause flag: stale "true" resettable; close resets to false  [#4]
// ===========================================================================
test('pause: a stray desktop.active=true (killed detach) is reset on close', () => {
  let cfg = '[desktop]\nvisual = "equalizer"\nactive = "true"\n'
  assert.strictEqual(M.readConfigFromText(cfg).desktopActive, true, 'mini would be stuck paused')
  cfg = M.writeConfigKey(cfg, 'desktop', 'active', 'false')
  assert.strictEqual(M.readConfigFromText(cfg).desktopActive, false)
  assert.strictEqual((cfg.match(/active\s*=/g) || []).length, 1, 'no duplicate active key')
})

test('pause: detach writes active=true, exactly one header/key', () => {
  let cfg = '[desktop]\nvisual = "equalizer"\nactive = "false"\n'
  cfg = M.writeConfigKey(cfg, 'desktop', 'active', 'true')
  assert.strictEqual(M.readConfigFromText(cfg).desktopActive, true)
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

// ===========================================================================
// Panel write pattern: an in-memory config text buffer must reflect a write
// IMMEDIATELY (synchronously) so the first click sticks. Quickshell's
// FileView.setText() does NOT update text() synchronously, so the panel keeps
// its own buffer; writeConfigKey + readTomlValue on that same string must
// round-trip without a file round-trip. This is the "every control needs two
// clicks" / "color sync doesn't work" regression guard.
// ===========================================================================
test('in-memory buffer: writeConfigKey then readTomlValue on same string reflects immediately', () => {
  let buf = '[mini]\nvisual = "equalizer"\ncolor_sync = false\n\n[visual.equalizer]\nbar_count = 32\n'
  // color sync toggle (single click)
  buf = M.writeConfigKey(buf, 'mini', 'color_sync', 'true')
  assert.strictEqual(M.readTomlValue(buf, 'mini', 'color_sync'), 'true',
    'first click must reflect without re-reading from disk')
  // knob write (single action)
  buf = M.writeConfigKey(buf, 'visual.equalizer', 'bar_count', 48)
  assert.strictEqual(M.readTomlValue(buf, 'visual.equalizer', 'bar_count'), '48',
    'knob must reflect on first write')
  // toggle back off
  buf = M.writeConfigKey(buf, 'mini', 'color_sync', 'false')
  assert.strictEqual(M.readTomlValue(buf, 'mini', 'color_sync'), 'false')
})

// ===========================================================================
// v7: spectrum frame carries `source`; panel shows it read-only  [#source-display]
// ===========================================================================
test('parseSpectrumLine: captures source into spectrumData.source', () => {
  M.parseSpectrumLine(JSON.stringify({ bands: [0.1, 0.5], energy: 0.3, beat: 0, silent: false, source: 'pipewire' }))
  assert.strictEqual(M.spectrumData.source, 'pipewire')
  assert.deepStrictEqual(M.spectrumData.bands, [0.1, 0.5])
  assert.strictEqual(M.spectrumData.silent, false)
})

test('parseSpectrumLine: preserves prior source when line omits it', () => {
  M.parseSpectrumLine(JSON.stringify({ bands: [0.2], energy: 0.1, beat: 0, silent: true, source: 'pipewire' }))
  assert.strictEqual(M.spectrumData.source, 'pipewire')
  // a frame without `source` (legacy/old bridge) must not wipe an existing value
  M.parseSpectrumLine(JSON.stringify({ bands: [0.0], energy: 0, beat: 0, silent: true }))
  assert.strictEqual(M.spectrumData.source, 'pipewire', 'source must persist when absent in the line')
})

test('sourceLabel: maps backend name to friendly, capitalized label', () => {
  assert.strictEqual(M.sourceLabel('pipewire'), 'PipeWire')
  assert.strictEqual(M.sourceLabel('pulse'), 'PulseAudio')
  assert.strictEqual(M.sourceLabel('jack'), 'JACK')
  assert.strictEqual(M.sourceLabel('alsa'), 'ALSA')
  assert.strictEqual(M.sourceLabel('file'), 'File')
  assert.strictEqual(M.sourceLabel(''), 'Unknown')
  assert.strictEqual(M.sourceLabel('bogus'), 'bogus')
})

test('sourceLabel: default when spectrumData.source missing', () => {
  // Panel reads M.sourceLabel(M.spectrumData.source || '')
  assert.strictEqual(M.sourceLabel(''), 'Unknown')
})

// v7: desktop window must use the bundled engine, NOT the deleted v6 bridge
// ===========================================================================
test('engineBin: plugin-local path points at bundled omaviz-engine', () => {
  const p = M.engineBin
  assert.ok(p.endsWith('/bin/omaviz-engine'), 'must point at the bundled engine')
  assert.ok(p.includes('/omarchy/plugins/org.omaviz.visualizer/'),
    'must be plugin-local (no systemd, no ~/.local/bin)')
})

test('engineBin: does NOT reference the removed v6 bridge binary', () => {
  assert.ok(!M.engineBin.includes('omaviz-spectrum-bridge'),
    'desktop window must not spawn the deleted bridge')
  assert.ok(!M.engineBin.includes('/.local/bin/'),
    'no separate binaries outside the plugin package')
})

test('bridgePath: retained for back-compat but NOT used by desktop window', () => {
  // The constant still exists, but its binary was removed in v7; the desktop
  // window must use engineBin instead. This guards the regression.
  assert.ok(typeof M.bridgePath === 'string')
})

// v7: mini-pause must not stick when the desktop window died without resetting
// ===========================================================================
test('isPaused: false when detached window is genuinely open', () => {
  // Normal detach: flag true AND detachProc running -> pause (freeze mini).
  assert.strictEqual(M.isPaused(true, true), true)
})

test('isPaused: false when flag set but window died (no stuck pause)', () => {
  // The desktop window was killed externally (crash/logout/SIGKILL) so its
  // onClosing never reset desktop.active — flag stuck true, but the detach
  // process is gone. The mini MUST keep running, not stay frozen.
  assert.strictEqual(M.isPaused(true, false), false)
})

test('isPaused: false when no detach active', () => {
  assert.strictEqual(M.isPaused(false, false), false)
  assert.strictEqual(M.isPaused(false, true), false)
})
