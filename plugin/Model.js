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
  d.bands = readTomlInt(tomlText, "audio", "bands") ?? d.bands
  d.gap = parseFloat(readTomlValue(tomlText, "mini", "gap") ?? "NaN")
  if (d.gap !== d.gap || d.gap < 0) d.gap = 3   // NaN/negative → default 3
  d.widthScale = parseFloat(readTomlValue(tomlText, "mini", "width_scale") ?? "1.5")
  if (d.widthScale !== d.widthScale || d.widthScale < 0.5 || d.widthScale > 4) d.widthScale = 1.5
  d.desktopActive = readTomlValue(tomlText, "desktop", "active") === "true"
  // Heartbeat lease (epoch ms, written by the open desktop window every 2s).
  // Guards against a stranded active=true with no live window.
  d.desktopHeartbeat = parseInt(readTomlValue(tomlText, "desktop", "heartbeat") ?? "0", 10)
  if (d.desktopHeartbeat !== d.desktopHeartbeat) d.desktopHeartbeat = 0
  d.colorSync = readTomlValue(tomlText, "mini", "color_sync") === "true"
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
  d.mono = readTomlValue(tomlText, "desktop", "mono") === "true"
  d.linearFall = readTomlValue(tomlText, "desktop", "linear_fall") === "true"
  d.scope = readTomlValue(tomlText, "desktop", "scope") === "true"
  d.artMode = readTomlValue(tomlText, "desktop", "artwork_mode") === "true"
    || readTomlValue(tomlText, "desktop", "immersive") === "true"   // pre-rename key
  d.artwork = readTomlValue(tomlText, "desktop", "artwork") !== "false"
  d.scopeThickness = readTomlFloat(tomlText, "desktop", "scope_thickness") ?? 2
  if (d.scopeThickness !== d.scopeThickness || d.scopeThickness < 1) d.scopeThickness = 1
  if (d.scopeThickness > 5) d.scopeThickness = 5
  d.dots = readTomlValue(tomlText, "desktop", "dots") !== "false"
  d.reflect = readTomlValue(tomlText, "desktop", "reflect") === "true"
  return d
}

function defaultConfig() {
  return {
    sensitivity: 1.0,
    bands: 32,
    gap: 3,
    widthScale: 1.5,
    desktopActive: false,
    desktopHeartbeat: 0,
    colorSync: false,
    themeBottom: "#e68e0d",
    themeTop: "#f59e0b",
    fire: false,
    peaks: true, peakFalloff: 0.5, spikes: false, splits: false, mono: false,
    linearFall: false, scope: false, artMode: false, artwork: true, scopeThickness: 2, dots: true, reflect: false,
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

// ---- Spectrum ----

// Holds the latest spectrum frame (updated by QML Process stdout)
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

// Parse a JSON line from spectrum-bridge / omaviz-engine stdout
function parseSpectrumLine(jsonLine) {
  try {
    var data = JSON.parse(jsonLine)
    // Oscilloscope feed: standalone {wave:[...]} line (see --wave).
    if (data && Array.isArray(data.wave) && !Array.isArray(data.bands)) {
      spectrumData.wave = data.wave
      return
    }
    if (data && Array.isArray(data.bands)) {
      spectrumData.bands = data.bands
      spectrumData.energy = data.energy !== undefined ? data.energy : 0
      spectrumData.beat = data.beat !== undefined ? data.beat : 0
      spectrumData.silent = data.silent === true
      // Emission timestamp (ms epoch): lets consumers measure pipeline lag.
      if (data.t !== undefined) spectrumData.t = data.t
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

// ---- Desktop mode ----
function isDesktopActiveFromText(tomlText) {
  return readTomlValue(tomlText, "desktop", "active") === "true"
}

// ---- Module exports ----
if (typeof module !== "undefined") {
  module.exports = {
    configPath: configPath,
    readConfigFromText: readConfigFromText,
    defaultConfig: defaultConfig,
    writeConfigKey: writeConfigKey,
    parseSpectrumLine: parseSpectrumLine,
    spectrumData: spectrumData,
    isDesktopActiveFromText: isDesktopActiveFromText,
    readTomlTopKey: readTomlTopKey,
    engineBin: engineBin
  }
}
