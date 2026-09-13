.pragma library

// Model.js — shared singleton for the omaviz v2 Omarchy plugin.
//
// .pragma library makes this a SINGLETON: both BarWidget.qml and Panel.qml
// import it as `import "Model.js" as Model`, so they share one instance.
// The bar's spectrum Process writes into Model.spectrumData; the panel reads
// the same object. Without the pragma each file would get its own copy and
// the panel would never see live data.

// ---- Paths ----
// NOTE: .pragma library modules cannot see the Quickshell global at load
// time ("Quickshell is not defined"), so we resolve HOME defensively.
// In the shell runtime Quickshell is defined; under node/standalone it is
// not, so fall back rather than throw.
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
// no ~/.local/bin). The bar widget and the detached desktop window both spawn
// this. Path is derivable from HOME so the standalone Desktop.qml (which has no
// moduleName) can reach it without Quickshell shell globals.
var pluginDir = home + "/.config/omarchy/plugins/org.omaviz.visualizer"
var engineBin = pluginDir + "/bin/omaviz-engine"

// ---- TOML helpers ----

// Read a value from a TOML section:key line
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
  // Heartbeat lease (epoch ms, written by the open desktop window every 2s).
  // Guards against a stranded active=true with no live window.
  d.desktopHeartbeat = parseInt(readTomlValue(tomlText, "desktop", "heartbeat") ?? "0", 10)
  if (d.desktopHeartbeat !== d.desktopHeartbeat) d.desktopHeartbeat = 0
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
  // v7.7 settings panel options (live-wired, defaults: peaks on).
  d.peaks = readTomlValue(tomlText, "desktop", "peaks") !== "false"
  d.peakFalloff = readTomlFloat(tomlText, "desktop", "peak_falloff") ?? 0.5
  if (d.peakFalloff !== d.peakFalloff || d.peakFalloff < 0) d.peakFalloff = 0
  if (d.peakFalloff > 1) d.peakFalloff = 1
  d.spikes = readTomlValue(tomlText, "desktop", "spikes") === "true"
  d.splits = readTomlValue(tomlText, "desktop", "splits") === "true"
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
    desktopHeartbeat: 0,
    colorSync: false,
    gpu: true,
    border: true,
    colorSource: "theme",
    customColor: "#5ec8ff",
    themeBottom: "#e68e0d",
    themeTop: "#f59e0b",
    fire: false,
    peaks: true, peakFalloff: 0.5, spikes: false, splits: false,
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
  if (typeof value === "string" && !/^[\[\{]/.test(v.trim()) && !/^".*"$/.test(v.trim())) {
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

// ---- Visualizations ----

function parseVisualToml(tomlText, name) {
  var label = name
  var description = ""
  var params = []
  var currentParam = null

  if (!tomlText) return { name, label, description, params: [] }

  var currentParamIndex = -1
  function flush() {
    if (currentParam && currentParam.name) params.push(currentParam)
    currentParamIndex = -1
  }

  var lines = String(tomlText).split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (line.startsWith("#") || line === "") continue

    if (line.startsWith("label =") || line.startsWith("description =")) {
      if (currentParamIndex >= 0) {
        // Belongs to the current [[params]] table.
        var pk0 = line.split("=")[0].trim()
        var pv0 = line.split("=").slice(1).join("=").trim().replace(/^["']|["']$/g, "")
        if (pk0 === "label") currentParam.label = pv0
        else if (pk0 === "description") currentParam.description = pv0
      } else {
        // Top-level visual label/description.
        if (line.startsWith("label =")) label = line.split("=")[1].trim().replace(/^["']|["']$/g, "")
        else if (line.startsWith("description =")) description = line.split("=")[1].trim().replace(/^["']|["']$/g, "")
      }
      continue
    }

    if (line.indexOf("params") >= 0 && line.startsWith("[")) {
      // A [[params]] table starts a new param object. Flush any previous one.
      if (currentParamIndex >= 0) flush()
      currentParam = { name: null, label: null, default: 0, min: 0, max: 1, type: "float", help: "" }
      currentParamIndex = params.length
    } else if (currentParam && line.indexOf("=") >= 0) {
      // Lines belonging to the current param table.
      var pk = line.split("=")[0].trim()
      var pv = line.split("=").slice(1).join("=").trim().replace(/^["']|["']$/g, "")
      if (pk === "name") currentParam.name = pv
      else if (pk === "label") currentParam.label = pv
      else if (pk === "default") currentParam.default = parseFloat(pv) || 0
      else if (pk === "min") currentParam.min = parseFloat(pv) || 0
      else if (pk === "max") currentParam.max = parseFloat(pv) || 1
      else if (pk === "type") currentParam.type = pv
      else if (pk === "boolean") currentParam.boolean = (pv === "true")
      else if (pk === "help") currentParam.help = pv
    }
    // A non-params section header (e.g. [other]) ends param parsing.
    else if (line.startsWith("[") && line.indexOf("params") < 0) {
      flush()
      currentParam = null
      currentParamIndex = -1
    }
  }
  flush()

  return { name, label, description, params }
}

function discoverVisualsFromText(tomlFiles) {
  // tomlFiles: array of { path, text }
  var result = []
  for (var i = 0; i < tomlFiles.length; i++) {
    var path = tomlFiles[i].path
    var name = path.replace(/.*\/([^/]+)\.toml$/, "$1")
    var visual = parseVisualToml(tomlFiles[i].text, name)
    if (visual.label) {
      result.push(visual)
    }
  }
  result.sort(function(a, b) {
    return String(a.label).localeCompare(String(b.label))
  })
  return result
}

// Get param declarations for a visual's .toml text
function visualParamsFromText(tomlText, name) {
  var v = parseVisualToml(tomlText, name)
  // Tag each param with the visual it belongs to, so the panel writes
  // knob edits back to the correct [visual.<name>] section.
  for (var i = 0; i < v.params.length; i++) v.params[i].source = name
  return v.params
}

// Read current config values for a visual's params.
// User-edited values live in config.toml under [visual.<source>], where
// <source> is the visual each param belongs to (tagged by visualParamsFromText).
// The shared config text is passed in so we read the user's saved values.
function visualConfigValues(configText, params) {
  var values = {}
  for (var i = 0; i < params.length; i++) {
    var p = params[i]
    var section = "visual." + (p.source || p.visual || "equalizer")
    var v = readTomlValue(configText, section, p.name)
    if (v !== null) {
      if (p.type === "boolean") values[p.name] = (v === "true")
      else if (p.boolean === true) values[p.name] = (v === "true")
      else values[p.name] = parseFloat(v) || p.default
    } else {
      values[p.name] = p.default
    }
  }
  return values
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

// ---- Spectrum ----

// Holds the latest spectrum frame (updated by QML Process stdout)
var spectrumData = {
  bands: [],
  energy: 0,
  beat: 0,
  silent: true,
  source: "",
  seq: 0
}

// Parse a JSON line from spectrum-bridge / omaviz-engine stdout
function parseSpectrumLine(jsonLine) {
  try {
    var data = JSON.parse(jsonLine)
    if (data && Array.isArray(data.bands)) {
      spectrumData.bands = data.bands
      spectrumData.energy = data.energy !== undefined ? data.energy : 0
      spectrumData.beat = data.beat !== undefined ? data.beat : 0
      spectrumData.silent = data.silent === true
      // Frame sequence: lets consumers (preview) skip reassignment when
      // the engine holds a frame to its heartbeat rate.
      spectrumData.seq++
      // v7: engine reports its resolved backend name. Preserve any prior value
      // when the line omits `source` (e.g. an older/legacy frame).
      if (typeof data.source === "string" && data.source.length > 0) {
        spectrumData.source = data.source
      }
    }
  } catch (e) {
    // malformed line — skip
  }
}

// Friendly, capitalized label for an audio backend name. Used by the panel's
// read-only SOURCE line. Unknown names pass through unchanged.
function sourceLabel(name) {
  var map = {
    pipewire: "PipeWire",
    pulse: "PulseAudio",
    jack: "JACK",
    alsa: "ALSA",
    file: "File"
  }
  if (!name) return "Unknown"
  return map[name] !== undefined ? map[name] : name
}

// ---- File IO helpers used by the panel ----
// (QML FileView is read-only on load; writing is done by the panel's own
//  writable FileView. These read helpers let the panel re-read after a write.)

// Read a whole file as text. Returns "" if missing.
function readFileText(path) {
  // QML owns file IO; this is a fallback used only when no FileView is wired.
  // The panel provides its content via Model.parseSpectrumLine-style hooks,
  // so we expose a no-throw stub that returns the last known value.
  return _fileCache[path] || ""
}

var _fileCache = {}

function cacheFileText(path, text) {
  _fileCache[path] = text
}

// Enumerate visual .toml files from the visuals dir (panel calls this after
// its visualsProc populates Model._visualFiles).
function listVisualFiles() {
  return _visualFiles
}

var _visualFiles = []

function setVisualFiles(files) {
  _visualFiles = files
}

// Redirect path helpers the panel references
function readTomlFile() { return "" }

// ---- Desktop mode ----
function isDesktopActiveFromText(tomlText) {
  return readTomlValue(tomlText, "desktop", "active") === "true"
}

// ---- Module exports ----
if (typeof module !== "undefined") {
  module.exports = {
    configPath: configPath,
    visualsDir: visualsDir,
    readConfigFromText: readConfigFromText,
    defaultConfig: defaultConfig,
    writeConfigKey: writeConfigKey,
    discoverVisualsFromText: discoverVisualsFromText,
    visualParamsFromText: visualParamsFromText,
    visualConfigValues: visualConfigValues,
    readAudioFromText: readAudioFromText,
    parseSpectrumLine: parseSpectrumLine,
    spectrumData: spectrumData,
    isDesktopActiveFromText: isDesktopActiveFromText,
    readFileText: readFileText,
    cacheFileText: cacheFileText,
    listVisualFiles: listVisualFiles,
    setVisualFiles: setVisualFiles,
    readTomlFile: readTomlFile,
    readTomlTopKey: readTomlTopKey,
    engineBin: engineBin
  }
}
