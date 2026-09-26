.pragma library

// ModelStore.js — Reactive config singleton for omaviz.
// .pragma library makes this a SINGLETON: BarWidget, Panel, Desktop all
// import it as `import "ModelStore.js" as Store` and share ONE instance.
// Changes via Store.set() emit changed(path, value) for QML bindings.

// ---- Paths ----
var home = "/home/kishan"
try {
  if (typeof Quickshell !== "undefined" && Quickshell.env) {
    home = Quickshell.env("HOME") || home
  } else if (typeof environment !== "undefined" && environment.HOME) {
    home = environment.HOME
  }
} catch (e) { /* keep default */ }
var configPath = home + "/.config/omaviz/config.toml"
var pluginDir = home + "/.config/omarchy/plugins/org.omaviz.visualizer"
var engineBin = pluginDir + "/bin/omaviz-engine"

// ---- Default Config (source of truth) ----
function defaultConfig() {
  return {
    audio: {
      sensitivity: 1.0,
      bands: 32,
      // smoothing removed — engine outputs raw; VisualCanvas does all physics
    },
    mini: {
      gap: 1,
      widthScale: 1.5,
      colorSync: true,          // theme gradient by default
    },
    desktop: {
      // Theme (auto-synced by BarWidget on theme change)
      themeBottom: "#e68e0d",
      themeTop: "#f59e0b",
      themeAccent: "#f59e0b",

      // Bar color override
      barColorCustom: false,
      barColorFrom: "#e68e0d",
      barColorTo: "#f59e0b",

      // Peak physics (single source of truth)
      peaks: true,
      peakFalloff: 0.1,         // initial fall speed (0.0-1.0)
      peakSustainMs: 100,       // hold at peak before falling
      linearFall: true,         // engine fall mode (kept for compat)

      // Visualization
      spikes: false,
      fire: false,
      stacks: false,
      scope: false,
      artwork: false,
      reflect: true,
      dots: true,
      scopeThickness: 2,
      mono: false,
      minBarHeight: false,
    },
  }
}

// ---- Internal State ----
var _state = defaultConfig()
var _listeners = {}   // path -> [callback, ...]
var _dirty = false
var _persistTimer = null

// ---- TOML Helpers ----
function readTomlValue(tomlText, section, key) {
  if (!tomlText) return null
  var lines = String(tomlText).split("\n")
  var inSection = (section === "")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (line.startsWith("#") || line === "") continue
    if (line.startsWith("[") && line.endsWith("]")) {
      inSection = (line.slice(1, -1).trim() === section)
      continue
    }
    if (inSection && line.indexOf("=") >= 0) {
      var parts = line.split("=")
      var k = parts[0].trim()
      var v = parts.slice(1).join("=").trim()
      if (k === key) {
        v = v.replace(/^["']|["']$/g, "")
        return v
      }
    }
  }
  return null
}

function readTomlFloat(tomlText, section, key) {
  var v = readTomlValue(tomlText, section, key)
  return v !== null ? parseFloat(v) : null
}

function readTomlInt(tomlText, section, key) {
  var v = readTomlValue(tomlText, section, key)
  return v !== null ? parseInt(v, 10) : null
}

function isHexColor(s) {
  return typeof s === "string" && /^#[0-9a-fA-F]{6}$/.test(s)
}

// ---- Load from TOML (bootstrap) ----
function loadFromTOML(tomlText) {
  var d = defaultConfig()
  if (!tomlText) { _state = d; return }

  d.audio.sensitivity = readTomlFloat(tomlText, "audio", "sensitivity") ?? d.audio.sensitivity
  d.audio.bands = readTomlInt(tomlText, "audio", "bands") ?? d.audio.bands

  d.mini.gap = parseFloat(readTomlValue(tomlText, "mini", "gap") ?? "NaN")
  if (d.mini.gap !== d.mini.gap || d.mini.gap < 0) d.mini.gap = 1
  d.mini.widthScale = parseFloat(readTomlValue(tomlText, "mini", "width_scale") ?? "1.5")
  if (d.mini.widthScale !== d.mini.widthScale || d.mini.widthScale < 0.5 || d.mini.widthScale > 4) d.mini.widthScale = 1.5
  d.mini.colorSync = readTomlValue(tomlText, "mini", "color_sync") === "true"

  d.desktop.themeBottom = readTomlValue(tomlText, "desktop", "theme_bottom") || d.desktop.themeBottom
  d.desktop.themeTop = readTomlValue(tomlText, "desktop", "theme_top") || d.desktop.themeTop
  d.desktop.themeAccent = readTomlValue(tomlText, "desktop", "theme_accent") || d.desktop.themeAccent
  if (!isHexColor(d.desktop.themeAccent)) d.desktop.themeAccent = d.desktop.themeTop

  d.desktop.barColorCustom = readTomlValue(tomlText, "desktop", "bar_color_custom") === "true"
  d.desktop.barColorFrom = readTomlValue(tomlText, "desktop", "bar_color_from") || d.desktop.barColorFrom
  d.desktop.barColorTo = readTomlValue(tomlText, "desktop", "bar_color_to") || d.desktop.barColorTo
  if (!isHexColor(d.desktop.barColorFrom)) d.desktop.barColorFrom = d.desktop.themeBottom
  if (!isHexColor(d.desktop.barColorTo)) d.desktop.barColorTo = d.desktop.themeTop

  d.desktop.peaks = readTomlValue(tomlText, "desktop", "peaks") !== "false"
  d.desktop.peakFalloff = readTomlFloat(tomlText, "desktop", "peak_falloff") ?? d.desktop.peakFalloff
  if (d.desktop.peakFalloff !== d.desktop.peakFalloff || d.desktop.peakFalloff < 0) d.desktop.peakFalloff = 0
  if (d.desktop.peakFalloff > 1) d.desktop.peakFalloff = 1
  d.desktop.peakSustainMs = readTomlInt(tomlText, "desktop", "peak_sustain_ms") ?? d.desktop.peakSustainMs
  if (d.desktop.peakSustainMs < 0) d.desktop.peakSustainMs = 0
  if (d.desktop.peakSustainMs > 1000) d.desktop.peakSustainMs = 1000

  d.desktop.linearFall = readTomlValue(tomlText, "desktop", "linear_fall") === "true"
  d.desktop.spikes = readTomlValue(tomlText, "desktop", "spikes") === "true"
  d.desktop.fire = readTomlValue(tomlText, "desktop", "fire") === "true"
  d.desktop.stacks = readTomlValue(tomlText, "desktop", "stacks") === "true"
    || readTomlValue(tomlText, "desktop", "splits") === "true"
  d.desktop.scope = readTomlValue(tomlText, "desktop", "scope") === "true"
  d.desktop.artwork = readTomlValue(tomlText, "desktop", "artwork") !== "false"
  d.desktop.reflect = readTomlValue(tomlText, "desktop", "reflect") === "true"
  d.desktop.dots = readTomlValue(tomlText, "desktop", "dots") !== "false"
  d.desktop.scopeThickness = readTomlFloat(tomlText, "desktop", "scope_thickness") ?? d.desktop.scopeThickness
  if (d.desktop.scopeThickness !== d.desktop.scopeThickness || d.desktop.scopeThickness < 1) d.desktop.scopeThickness = 1
  if (d.desktop.scopeThickness > 5) d.desktop.scopeThickness = 5
  d.desktop.mono = readTomlValue(tomlText, "desktop", "mono") === "true"
  d.desktop.minBarHeight = readTomlValue(tomlText, "desktop", "min_bar_height") === "true"

  _state = d
}

// ---- Reactive API ----
function _notify(path, value) {
  var cbs = _listeners[path]
  if (cbs) {
    for (var i = 0; i < cbs.length; i++) cbs[i](value)
  }
}

function get(path) {
  // path: "audio.sensitivity", "mini.colorSync", "desktop.peaks", etc.
  var parts = path.split(".")
  var obj = _state
  for (var i = 0; i < parts.length; i++) {
    if (obj === null || obj === undefined) return undefined
    obj = obj[parts[i]]
  }
  return obj
}

function set(path, value) {
  var parts = path.split(".")
  var obj = _state
  for (var i = 0; i < parts.length - 1; i++) {
    if (obj === null || obj === undefined) return false
    obj = obj[parts[i]]
  }
  var key = parts[parts.length - 1]
  if (obj[key] === value) return true  // no change
  obj[key] = value
  _notify(path, value)
  _schedulePersist()
  return true
}

function onChanged(path, callback) {
  if (!_listeners[path]) _listeners[path] = []
  _listeners[path].push(callback)
  // Return unsubscribe function
  return function() {
    var idx = _listeners[path].indexOf(callback)
    if (idx >= 0) _listeners[path].splice(idx, 1)
  }
}

// ---- Validation ----
function validate(path, value) {
  switch (path) {
    case "audio.sensitivity": return typeof value === "number" && value >= 0.1 && value <= 10
    case "audio.bands": return typeof value === "number" && value >= 4 && value <= 512
    case "mini.gap": return typeof value === "number" && value >= 0 && value <= 20
    case "mini.widthScale": return typeof value === "number" && value >= 0.5 && value <= 4
    case "mini.colorSync": return typeof value === "boolean"
    case "desktop.themeBottom":
    case "desktop.themeTop":
    case "desktop.themeAccent":
    case "desktop.barColorFrom":
    case "desktop.barColorTo":
      return isHexColor(value)
    case "desktop.barColorCustom":
    case "desktop.peaks":
    case "desktop.linearFall":
    case "desktop.spikes":
    case "desktop.fire":
    case "desktop.stacks":
    case "desktop.scope":
    case "desktop.artwork":
    case "desktop.reflect":
    case "desktop.dots":
    case "desktop.mono":
    case "desktop.minBarHeight":
      return typeof value === "boolean"
    case "desktop.peakFalloff": return typeof value === "number" && value >= 0 && value <= 1
    case "desktop.peakSustainMs": return typeof value === "number" && value >= 0 && value <= 1000
    case "desktop.scopeThickness": return typeof value === "number" && value >= 1 && value <= 5
    default: return true
  }
}

// ---- Persistence (debounced) ----
function _schedulePersist() {
  if (_dirty) return
  _dirty = true
  if (_persistTimer) return
  _persistTimer = setTimeout(function() {
    _persistTimer = null
    _dirty = false
    var txt = toTOML()
    // Async write via FileView would be ideal, but we expose toTOML()
    // BarWidget handles the actual FileView.setText() on its side
    if (typeof StorePersistRequest !== "undefined") {
      StorePersistRequest(txt)
    }
  }, 300)
}

function toTOML() {
  var s = _state
  var lines = []
  lines.push("[audio]")
  lines.push("sensitivity = " + s.audio.sensitivity)
  lines.push("bands = " + s.audio.bands)
  lines.push("")
  lines.push("[mini]")
  lines.push("gap = " + s.mini.gap)
  lines.push("width_scale = " + s.mini.widthScale)
  lines.push("color_sync = " + (s.mini.colorSync ? "true" : "false"))
  lines.push("")
  lines.push("[desktop]")
  lines.push("theme_bottom = \"" + s.desktop.themeBottom + "\"")
  lines.push("theme_top = \"" + s.desktop.themeTop + "\"")
  lines.push("theme_accent = \"" + s.desktop.themeAccent + "\"")
  lines.push("bar_color_custom = " + (s.desktop.barColorCustom ? "true" : "false"))
  lines.push("bar_color_from = \"" + s.desktop.barColorFrom + "\"")
  lines.push("bar_color_to = \"" + s.desktop.barColorTo + "\"")
  lines.push("peaks = " + (s.desktop.peaks ? "true" : "false"))
  lines.push("peak_falloff = " + s.desktop.peakFalloff)
  lines.push("peak_sustain_ms = " + s.desktop.peakSustainMs)
  lines.push("linear_fall = " + (s.desktop.linearFall ? "true" : "false"))
  lines.push("spikes = " + (s.desktop.spikes ? "true" : "false"))
  lines.push("fire = " + (s.desktop.fire ? "true" : "false"))
  lines.push("stacks = " + (s.desktop.stacks ? "true" : "false"))
  lines.push("scope = " + (s.desktop.scope ? "true" : "false"))
  lines.push("artwork = " + (s.desktop.artwork ? "true" : "false"))
  lines.push("reflect = " + (s.desktop.reflect ? "true" : "false"))
  lines.push("dots = " + (s.desktop.dots ? "true" : "false"))
  lines.push("scope_thickness = " + s.desktop.scopeThickness)
  lines.push("mono = " + (s.desktop.mono ? "true" : "false"))
  lines.push("min_bar_height = " + (s.desktop.minBarHeight ? "true" : "false"))
  lines.push("")
  lines.push("[full]")
  lines.push("visual = \"wave\"")
  return lines.join("\n")
}

// ---- TOML Mutation (for legacy UI writers) ----
function writeConfigKey(tomlText, section, key, value) {
  if (!tomlText) tomlText = toTOML()
  var lines = String(tomlText).split("\n")
  var inSection = (section === "")
  var found = false
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (line.startsWith("[") && line.endsWith("]")) {
      inSection = (line.slice(1, -1).trim() === section)
      continue
    }
    if (inSection && line.indexOf("=") >= 0) {
      var parts = line.split("=")
      var k = parts[0].trim()
      if (k === key) {
        // Preserve existing quote style
        var quoted = typeof value === "string" && !/^(true|false|[\d.]+)$/.test(value)
        lines[i] = key + " = " + (quoted ? "\"" + value + "\"" : value)
        found = true
        break
      }
    }
  }
  if (!found) {
    // Insert at end of section
    for (var i = lines.length - 1; i >= 0; i--) {
      var line = lines[i].trim()
      if (line.startsWith("[") && line.endsWith("]")) {
        var secName = line.slice(1, -1).trim()
        if (secName === section) {
          var quoted = typeof value === "string" && !/^(true|false|[\d.]+)$/.test(value)
          lines.splice(i + 1, 0, key + " = " + (quoted ? "\"" + value + "\"" : value))
          break
        }
      }
    }
  }
  return lines.join("\n")
}

// Hook for BarWidget to receive persist requests
// BarWidget sets: StorePersistRequest = function(txt) { detachConfigWrite.setText(txt) }
var StorePersistRequest = null

// ---- Spectrum Data (shared singleton) ----
var spectrumData = {
  bands: [],
  wave: [],
  energy: 0,
  beat: 0,
  silent: true,
  source: "",
  seq: 0,
  t: 0
}

function parseSpectrumLine(jsonLine) {
  try {
    var data = JSON.parse(jsonLine)
    if (data && Array.isArray(data.wave) && !Array.isArray(data.bands)) {
      spectrumData.wave = data.wave
      return
    }
    if (data && Array.isArray(data.bands)) {
      spectrumData.bands = data.bands
      spectrumData.energy = data.energy !== undefined ? data.energy : 0
      spectrumData.beat = data.beat !== undefined ? data.beat : 0
      spectrumData.silent = data.silent === true
      if (data.t !== undefined) spectrumData.t = data.t
      if (typeof data.source === "string" && data.source.length > 0) {
        spectrumData.source = data.source
      }
      spectrumData.seq++
    }
  } catch (e) {}
}

function sourceLabel(name) {
  var map = {
    pipewire: "PipeWire", pulse: "PulseAudio", jack: "JACK",
    alsa: "ALSA", file: "File"
  }
  if (!name) return "Unknown"
  return map[name] !== undefined ? map[name] : name
}

// ---- Exports ----
if (typeof module !== "undefined") {
  module.exports = {
    configPath: configPath,
    engineBin: engineBin,
    defaultConfig: defaultConfig,
    loadFromTOML: loadFromTOML,
    get: get,
    set: set,
    onChanged: onChanged,
    validate: validate,
    toTOML: toTOML,
    parseSpectrumLine: parseSpectrumLine,
    spectrumData: spectrumData,
    sourceLabel: sourceLabel,
  }
}