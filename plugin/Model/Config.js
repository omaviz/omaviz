// Model/Config.js — config TOML read/write, default config, path constants,
// file-cache helpers, visual-file enumeration, audio config helpers.
//
// Plain JS module (no pragma): imported by the Model.js facade under QML,
// loaded directly by node tests under Node. Each importer gets its own
// top-level scope copy.
//
// Owns ONLY config concerns (ADR-0003 §2 item 2): configPath/visualsDir/
// engineBin/bridgePath constants, readConfigFromText, defaultConfig,
// writeConfigKey, readAudioFromText, file-cache + visual-file helpers.

// ---- Paths ----
// NOTE: plain JS modules loaded by the facade live in the same QML context
// as the facade, so Quickshell/env are visible here at load time under QML.
// Under Node/standalone they are not, so fall back rather than throw.
var home = "/home/kishan"
try {
  if (typeof Quickshell !== "undefined" && Quickshell.env) {
    home = Quickshell.env("HOME") || home
  } else if (typeof environment !== "undefined" && environment.HOME) {
    home = environment.HOME
  }
} catch (e) { /* keep default */ }

var configPath = home + "/.config/omaviz/config.toml"
var visualsDir = home + "/.config/omaviz/visuals"

// v6 bridge binary (REMOVED in v7 — kept only as a constant for back-compat).
var bridgePath = home + "/.local/bin/omaviz-spectrum-bridge"

// v7 bundled engine: lives INSIDE the plugin package (no systemd, no socket,
// no ~/.local/bin). Path is derivable from HOME so standalone consumers can
// reach it without Quickshell shell globals.
var pluginDir = home + "/.config/omarchy/plugins/org.omaviz.visualizer"
var engineBin = pluginDir + "/bin/omaviz-engine"

// ---- TOML helpers ----

// Read a value from a TOML section:key line.
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

// Top-level (no-section) TOML key reader. Used for theme colors.toml.
function readTomlTopKey(tomlText, key) {
  return readTomlValue(tomlText, "", key)
}

function readTomlFloat(tomlText, section, key) {
  var v = readTomlValue(tomlText, section, key)
  return v !== null ? parseFloat(v) : null
}

function readTomlInt(tomlText, section, key) {
  var v = readTomlValue(tomlText, section, key)
  return v !== null ? parseInt(v, 10) : null
}

// ---- Config ----

function readConfigFromText(tomlText) {
  var d = defaultConfig()
  if (!tomlText) return d
  d.sensitivity = readTomlFloat(tomlText, "audio", "sensitivity") ?? d.sensitivity
  d.smoothing = readTomlFloat(tomlText, "audio", "smoothing") ?? d.smoothing
  d.bands = readTomlInt(tomlText, "audio", "bands") ?? d.bands
  // v7.6 desktop window bar density (spectrum resolution). The engine accepts
  // any N; the GL renderer's bar count is generalized by the GL track. The
  // Canvas-2D desktop fallback + bar preview already render bands.length.
  d.density = readTomlInt(tomlText, "desktop", "density") ?? d.density
  d.visualMini = readTomlValue(tomlText, "mini", "visual") ?? d.visualMini
  d.visualDesktop = readTomlValue(tomlText, "desktop", "visual") ?? d.visualDesktop
  d.visualFull = readTomlValue(tomlText, "full", "visual") ?? d.visualFull
  d.style = readTomlValue(tomlText, "mini", "style") ?? d.style
  d.gap = parseFloat(readTomlValue(tomlText, "mini", "gap") ?? "NaN")
  if (d.gap !== d.gap || d.gap < 0) d.gap = 3   // NaN/negative → default 3
  d.widthScale = parseFloat(readTomlValue(tomlText, "mini", "width_scale") ?? "1.5")
  if (d.widthScale !== d.widthScale || d.widthScale < 0.5 || d.widthScale > 4) d.widthScale = 1.5
  d.styleDesktop = readTomlValue(tomlText, "desktop", "style") ?? d.style
  d.desktopActive = readTomlValue(tomlText, "desktop", "active") === "true"
  d.colorSync = readTomlValue(tomlText, "mini", "color_sync") === "true"
  d.gpu = readTomlValue(tomlText, "desktop", "gpu") !== "false"
  // v7.2 visual options (window)
  d.border = readTomlValue(tomlText, "desktop", "border") !== "false"   // default true
  d.colorSource = readTomlValue(tomlText, "desktop", "color_source") || "theme"
  d.customColor = readTomlValue(tomlText, "desktop", "custom_color") || "#5ec8ff"
  // Theme gradient defaults: Matte Black active theme (see THEME_PALETTE.md).
  // accent (#e68e0d) -> bright_blue (#f59e0b). Replaces the old cyan/purple
  // (#19e0d4 / #a45cff) which did NOT match the active theme.
  d.themeBottom = readTomlValue(tomlText, "desktop", "theme_bottom") || "#e68e0d"
  d.themeTop = readTomlValue(tomlText, "desktop", "theme_top") || "#f59e0b"
  // v7.4 fire toggle: a top-level visualization option (independent of style)
  // that enables the winamp flame on the desktop renderer. Default OFF.
  d.fire = readTomlValue(tomlText, "desktop", "fire") === "true"
  // v7.4 Winamp-faithful per-visualization option sets (independent).
  d.eqMode = readTomlValue(tomlText, "visual.equalizer", "mode") || "bars"        // bars|lines
  d.eqColor = readTomlValue(tomlText, "visual.equalizer", "color") || "fire"      // solid|line|fade|fire
  d.eqGrid = readTomlValue(tomlText, "visual.equalizer", "grid") === "true"
  d.eqPeaks = readTomlValue(tomlText, "visual.equalizer", "peaks") !== "false"    // default on
  d.eqFalloff = readTomlFloat(tomlText, "visual.equalizer", "falloff") ?? 0.5      // 0 slow .. 1 fast
  d.eqZoom = readTomlValue(tomlText, "visual.equalizer", "zoom") || "1x"          // 1x|2x|4x
  d.eqThickness = readTomlInt(tomlText, "visual.equalizer", "thickness") || 2
  d.scopeStyle = readTomlValue(tomlText, "visual.oscilloscope", "style") || "line" // line|dot
  d.scopeColor = readTomlValue(tomlText, "visual.oscilloscope", "color") || "solid" // solid|line|fade|fire
  d.scopeGrid = readTomlValue(tomlText, "visual.oscilloscope", "grid") === "true"
  d.scopeScan = readTomlValue(tomlText, "visual.oscilloscope", "scan") === "true"
  d.scopeCentered = readTomlValue(tomlText, "visual.oscilloscope", "centered") === "true"
  d.scopeThickness = readTomlInt(tomlText, "visual.oscilloscope", "thickness") || 2
  return d
}

function defaultConfig() {
  return {
    sensitivity: 1.0,
    smoothing: 0.5,
    bands: 32,
    density: 128,       // desktop window spectrum resolution (dense/immersive default)
    visualMini: "equalizer",
    visualDesktop: "equalizer",
    visualFull: "wave",
    gap: 3,
    widthScale: 1.5,
    style: "classic",
    styleDesktop: "classic",
    desktopActive: false,
    colorSync: false,
    gpu: true,
    border: true,
    colorSource: "theme",
    customColor: "#5ec8ff",
    themeBottom: "#e68e0d",
    themeTop: "#f59e0b",
    fire: false,
    eqMode: "bars", eqColor: "fire", eqGrid: false, eqPeaks: true, eqFalloff: 0.5, eqZoom: "1x", eqThickness: 2,
    scopeStyle: "line", scopeColor: "solid", scopeGrid: false, scopeScan: false, scopeCentered: true, scopeThickness: 2
  }
}

// Write a single key in a TOML section. Returns the new file content.
// Conservative: updates in place, appends section/key if missing.
function writeConfigKey(tomlText, section, key, value) {
  if (!tomlText) {
    tomlText = "[audio]\nsensitivity = 1.0\nsmoothing = 0.5\nbands = 32\n\n[mini]\nvisual = \"equalizer\"\nstyle = \"classic\"\ncolor_sync = false\n\n[desktop]\nvisual = \"equalizer\"\ndensity = 128\n\n[full]\nvisual = \"wave\"\n"
  }
  var lines = tomlText.split("\n")
  var header = "[" + section + "]"
  var targetIdx = -1
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].trim() === header) { targetIdx = i; break }
  }

  // Build the value string. Quote string values so the result is valid TOML
  // for the strict omaviz daemon (which rejects unquoted strings like
  // `style = classic`). Numbers/booleans stay unquoted.
  var v = String(value)
  // Quote strings, but never double-quote a value that is already quoted
  if (typeof value === "string" && !/^[[\{]/.test(v.trim()) && !/^".*"$/.test(v.trim())) {
    v = '"' + v.replace(/^"|"$/g, '') + '"'
  }
  var entry = key + " = " + v

  if (targetIdx === -1) {
    // Section missing: append it (with a blank line before if needed).
    if (lines.length && lines[lines.length - 1].trim() !== "") lines.push("")
    lines.push(header)
    lines.push(entry)
    return lines.join("\n")
  }

  // Section exists. Look for the key within it (until next [section]).
  var keyIdx = -1
  for (var j = targetIdx + 1; j < lines.length; j++) {
    var t = lines[j].trim()
    if (t.startsWith("[") && t.endsWith("]")) break
    if (t.indexOf("=") >= 0 && t.split("=")[0].trim() === key) { keyIdx = j; break }
  }

  if (keyIdx !== -1) {
    lines[keyIdx] = entry
  } else {
    // Insert right after the header line.
    lines.splice(targetIdx + 1, 0, entry)
  }
  return lines.join("\n")
}

// ---- Audio config helpers ----

function readAudioFromText(tomlText) {
  if (!tomlText) return { sensitivity: 1.0, smoothing: 0.5, bands: 32 }
  return {
    sensitivity: readTomlFloat(tomlText, "audio", "sensitivity") ?? 1.0,
    smoothing: readTomlFloat(tomlText, "audio", "smoothing") ?? 0.5,
    bands: readTomlInt(tomlText, "audio", "bands") ?? 32
  }
}

// ---- File IO helpers (panel reads via Model, writes via its own FileView) ----

// Read a whole file as text. Returns "" if missing.
// QML owns file IO; this is a fallback used only when no FileView is wired.
var _fileCache = {}
function readFileText(path) {
  return _fileCache[path] || ""
}
function cacheFileText(path, text) {
  _fileCache[path] = text
}

// Enumerate visual .toml files (panel calls this after its visualsProc populates
// Model._visualFiles).
var _visualFiles = []
function listVisualFiles() {
  return _visualFiles
}
function setVisualFiles(files) {
  _visualFiles = files
}

// Redirect path helper the panel references.
function readTomlFile() { return "" }

// ---- Node export (test harness + any standalone Consumer) ----
if (typeof module !== "undefined") {
  module.exports = {
    configPath: configPath,
    visualsDir: visualsDir,
    bridgePath: bridgePath,
    engineBin: engineBin,
    readTomlValue: readTomlValue,
    readTomlTopKey: readTomlTopKey,
    readTomlFloat: readTomlFloat,
    readTomlInt: readTomlInt,
    readConfigFromText: readConfigFromText,
    defaultConfig: defaultConfig,
    writeConfigKey: writeConfigKey,
    readAudioFromText: readAudioFromText,
    readFileText: readFileText,
    cacheFileText: cacheFileText,
    listVisualFiles: listVisualFiles,
    setVisualFiles: setVisualFiles,
    readTomlFile: readTomlFile
  }
}
