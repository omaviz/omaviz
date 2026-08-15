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

// ---- TOML helpers ----

// Read a value from a TOML section:key line
function readTomlValue(tomlText, section, key) {
  if (!tomlText) return null
  var lines = String(tomlText).split("\n")
  var inSection = false
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

// ---- Config ----

function readConfigFromText(tomlText) {
  var d = defaultConfig()
  if (!tomlText) return d
  d.sensitivity = readTomlFloat(tomlText, "audio", "sensitivity") ?? d.sensitivity
  d.smoothing = readTomlFloat(tomlText, "audio", "smoothing") ?? d.smoothing
  d.bands = readTomlInt(tomlText, "audio", "bands") ?? d.bands
  d.visualMini = readTomlValue(tomlText, "mini", "visual") ?? d.visualMini
  d.visualDesktop = readTomlValue(tomlText, "desktop", "visual") ?? d.visualDesktop
  d.visualFull = readTomlValue(tomlText, "full", "visual") ?? d.visualFull
  d.desktopActive = readTomlValue(tomlText, "desktop", "active") === "true"
  return d
}

function defaultConfig() {
  return {
    sensitivity: 1.0,
    smoothing: 0.5,
    bands: 32,
    visualMini: "equalizer",
    visualDesktop: "equalizer",
    visualFull: "wave",
    desktopActive: false
  }
}

// Write a single key in a TOML section. Returns the new file content.
// Conservative: updates in place, appends section/key if missing.
function writeConfigKey(tomlText, section, key, value) {
  if (!tomlText) {
    tomlText = "[audio]\nsensitivity = 1.0\nsmoothing = 0.5\nbands = 32\n\n[mini]\nvisual = \"equalizer\"\n\n[desktop]\nvisual = \"equalizer\"\n\n[full]\nvisual = \"wave\"\n"
  }
  var lines = tomlText.split("\n")
  var inSection = false
  var found = false
  var out = []

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    var trimmed = line.trim()

    if (trimmed.startsWith("#") || trimmed === "") {
      out.push(line)
      continue
    }

    if (trimmed.startsWith("[") && trimmed.endsWith("]")) {
      inSection = (trimmed.slice(1, -1).trim() === section)
      out.push(line)
      continue
    }

    if (inSection && trimmed.indexOf("=") >= 0) {
      var parts = trimmed.split("=")
      var k = parts[0].trim()
      if (k === key) {
        var v = String(value)
        if (typeof value === "string" && (key === "visual" || key === "active")) {
          v = '"' + v + '"'
        }
        out.push(parts[0] + " = " + v)
        found = true
        continue
      }
    }
    out.push(line)
  }

  if (!found) {
    var sectionExists = false
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].trim().startsWith("[" + section + "]")) {
        sectionExists = true
        break
      }
    }
    if (!sectionExists) {
      out.push("[" + section + "]")
    }
    var v = String(value)
    if (typeof value === "string" && (key === "visual" || key === "active")) {
      v = '"' + v + '"'
    }
    out.push(key + " = " + v)
  }

  return out.join("\n")
}

// ---- Visualizations ----

function parseVisualToml(tomlText, name) {
  var label = name
  var description = ""
  var params = []
  var currentParam = null

  if (!tomlText) return { name, label, description, params: [] }

  var lines = String(tomlText).split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (line.startsWith("#") || line === "") continue

    if (line.startsWith("label =")) {
      label = line.split("=")[1].trim().replace(/^["']|["']$/g, "")
    } else if (line.startsWith("description =")) {
      description = line.split("=")[1].trim().replace(/^["']|["']$/g, "")
    } else if (line.startsWith("[params]") || (line.startsWith("[") && line.indexOf("params") >= 0)) {
      // Read params until next section
      for (var j = i + 1; j < lines.length; j++) {
        var pl = lines[j].trim()
        if (pl.startsWith("#")) continue
        if (pl.startsWith("[") || pl === "") break
        if (pl.indexOf("=") >= 0) {
          var pk = pl.split("=")[0].trim()
          var pv = pl.split("=").slice(1).join("=").trim().replace(/^["']|["']$/g, "")

          if (pk === "name") {
            if (currentParam && currentParam.name) {
              params.push(currentParam)
            }
            currentParam = { name: pv, label: pv, default: 0, min: 0, max: 1, type: "float", help: "" }
          } else if (currentParam) {
            if (pk === "label") currentParam.label = pv
            else if (pk === "default") currentParam.default = parseFloat(pv) || 0
            else if (pk === "min") currentParam.min = parseFloat(pv) || 0
            else if (pk === "max") currentParam.max = parseFloat(pv) || 1
            else if (pk === "type") currentParam.type = pv
            else if (pk === "help") currentParam.help = pv
          }
        }
      }
      if (currentParam && currentParam.name) {
        params.push(currentParam)
      }
      break
    }
  }

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
  return v.params
}

// Read current config values for a visual's params
function visualConfigValues(tomlText, visualName, params) {
  var values = {}
  for (var i = 0; i < params.length; i++) {
    var p = params[i]
    var v = readTomlValue(tomlText, visualName, p.name)
    if (v !== null) {
      values[p.name] = p.type === "boolean" ? (v === "true") : (parseFloat(v) || p.default)
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
  silent: true
}

// Parse a JSON line from spectrum-bridge stdout
function parseSpectrumLine(jsonLine) {
  try {
    var data = JSON.parse(jsonLine)
    if (data && Array.isArray(data.bands)) {
      spectrumData.bands = data.bands
      spectrumData.energy = data.energy !== undefined ? data.energy : 0
      spectrumData.beat = data.beat !== undefined ? data.beat : 0
      spectrumData.silent = data.silent === true
    }
  } catch (e) {
    // malformed line — skip
  }
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
    readTomlFile: readTomlFile
  }
}
