// Model/Spectrum.js — engine-frame → QML data path: spectrum parsing, shared
// spectrumData, pause resolution, source labeling, and the raw TOML readers
// that the facade re-exports for per-frame consumers.
//
// Plain JS module (no pragma): imported by the Model.js facade under QML,
// loaded directly by node tests under Node. Each importer gets its own
// top-level scope copy.
//
// Owns ONLY the frame→data concern (ADR-0003 §2 item 2): parseSpectrumLine,
// spectrumData (shared mutable), isPaused, isDesktopActiveFromText,
// sourceLabel, and the raw TOML readers (readTomlValue/readTomlFloat/
// readTomlInt) that the facade re-exports on behalf of per-frame consumers.

// ---- Shared spectrum state (updated by the QML Process stdout parser) ----

var spectrumData = {
  bands: [],
  energy: 0,
  beat: 0,
  silent: true,
  source: ""
}

// ---- Spectrum frame parsing ----

// Parse a JSON line from spectrum-bridge / omaviz-engine stdout
function parseSpectrumLine(jsonLine) {
  try {
    var data = JSON.parse(jsonLine)
    if (data && Array.isArray(data.bands)) {
      spectrumData.bands = data.bands
      spectrumData.energy = data.energy !== undefined ? data.energy : 0
      spectrumData.beat = data.beat !== undefined ? data.beat : 0
      spectrumData.silent = data.silent === true
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

// ---- Audio backend labeling ----

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

// ---- Desktop active / pause resolution ----

// The mini player freezes while the detached desktop window is open. Pause is
// derived from TWO signals so a stale on-disk flag can never freeze the mini
// forever:
//   - cfgActive:  desktop.active === "true" in config.toml (set on detach)
//   - detachRunning: the Panel's detachProc is genuinely still running
// If the desktop window is killed externally (crash / logout / SIGKILL) its
// onClosing handler never runs, leaving cfgActive stuck true — but the detach
// process exits, so detachRunning becomes false and we DO NOT pause. This
// prevents the "mini stuck paused" failure mode.
function isPaused(cfgActive, detachRunning) {
  return cfgActive === true && detachRunning === true
}

// ---- Desktop mode ----

function isDesktopActiveFromText(tomlText) {
  return readTomlValue(tomlText, "desktop", "active") === "true"
}

// ---- Raw TOML readers (low-level; re-exported on the facade) ----

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

function readTomlFloat(tomlText, section, key) {
  var v = readTomlValue(tomlText, section, key)
  return v !== null ? parseFloat(v) : null
}

function readTomlInt(tomlText, section, key) {
  var v = readTomlValue(tomlText, section, key)
  return v !== null ? parseInt(v, 10) : null
}

// ---- Node export (test harness + any standalone consumer) ----
if (typeof module !== "undefined") {
  module.exports = {
    spectrumData: spectrumData,
    parseSpectrumLine: parseSpectrumLine,
    sourceLabel: sourceLabel,
    isDesktopActiveFromText: isDesktopActiveFromText,
    isPaused: isPaused,
    readTomlValue: readTomlValue,
    readTomlFloat: readTomlFloat,
    readTomlInt: readTomlInt
  }
}
