.pragma library

// Pure settings, path, and frame helpers. QML components own runtime state.

// ---- Paths ----
// Resolve the user's home WITHOUT a hardcoded username: a literal home path
// would mis-resolve config + engine paths for EVERY other user of this plugin.
//   1. Quickshell.env("HOME")   — shell runtime
//   2. environment.HOME         — node / standalone fallback
//   3. derived from this file's own URL  (<home>/.config/omarchy/plugins/<id>/)
// Never throw: a .pragma library evaluates at load time, and an exception
// here kills the whole plugin. A .pragma library cannot see the Quickshell
// global at load time in every context, hence the defensive probe.
function _deriveHome() {
  try {
    if (typeof Quickshell !== "undefined" && Quickshell.env) {
      var h = Quickshell.env("HOME")
      if (h) return h
    }
  } catch (e) { /* fall through */ }
  try {
    if (typeof environment !== "undefined" && environment.HOME) {
      return environment.HOME
    }
  } catch (e) { /* fall through */ }
  // Last resort: this module lives at <home>/.config/omarchy/plugins/<id>/.
  try {
    if (typeof Qt !== "undefined" && Qt.resolvedUrl) {
      var u = String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "")
      var marker = "/.config/omarchy/plugins/"
      var i = u.indexOf(marker)
      if (i > 0) return u.slice(0, i)
    }
  } catch (e) { /* fall through */ }
  return ""
}

// Plugin dir is derivable from THIS module's URL (not HOME), so a non-standard
// install location or the standalone Desktop.qml still resolves correctly.
function _derivePluginDir() {
  try {
    if (typeof Qt !== "undefined" && Qt.resolvedUrl) {
      var dir = String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "")
      if (dir) return dir.replace(/\/$/, "")
    }
  } catch (e) { /* fall through */ }
  return _home + "/.config/omarchy/plugins/org.omaviz.visualizer"
}

// Config dir honours XDG_CONFIG_HOME when set, else ~/.config.
function _deriveConfigDir() {
  var xdg = ""
  try {
    if (typeof Quickshell !== "undefined" && Quickshell.env) {
      xdg = Quickshell.env("XDG_CONFIG_HOME") || ""
    }
  } catch (e) { /* fall through */ }
  if (!xdg) {
    try {
      if (typeof environment !== "undefined" && environment.XDG_CONFIG_HOME) {
        xdg = environment.XDG_CONFIG_HOME
      }
    } catch (e) { /* fall through */ }
  }
  return xdg ? xdg : (_home + "/.config")
}

var _home = _deriveHome()
var configPath = _deriveConfigDir() + "/omaviz/config.toml"
// Runtime lease is separate: desktop heartbeats must never overwrite settings.
var desktopStatePath = _deriveConfigDir() + "/omaviz/desktop-state.toml"
// Bundled engine: lives INSIDE the plugin package (no systemd, no socket,
// no ~/.local/bin). The bar widget and the detached desktop window both spawn
// this.
var pluginDir = _derivePluginDir()
var engineBin = pluginDir + "/bin/omaviz-engine"

// ---- TOML helpers ----

// Ignore inline comments without treating a quoted hex colour as a comment.
function stripTomlComment(line) {
  var quote = "", escaped = false
  for (var i = 0; i < line.length; i++) {
    var c = line[i]
    if (escaped) { escaped = false; continue }
    if (quote === '"' && c === String.fromCharCode(92)) { escaped = true; continue }
    if (quote) { if (c === quote) quote = "" }
    else if (c === '"' || c === "'") quote = c
    else if (c === "#") return line.slice(0, i)
  }
  return line
}

// Read a value from a TOML section:key line
function readTomlValue(tomlText, section, key) {
  if (!tomlText) return null
  var lines = String(tomlText).split("\n")
  var inSection = (section === "")
  for (var i = 0; i < lines.length; i++) {
    var line = stripTomlComment(lines[i]).trim()
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
        v = stripTomlComment(v).trim()
        if (v[0] === '"') {
          try { return JSON.parse(v) } catch (e) { return null }
        }
        if (v[0] === "'" && v[v.length - 1] === "'") return v.slice(1, -1)
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

// Strict #rrggbb validator for user-supplied custom bar tones.
// Anything else falls back to the theme pair (never throws in QML).
function isHexColor(s) {
  return typeof s === "string" && /^#[0-9a-fA-F]{6}$/.test(s)
}

function readTomlFloat(tomlText, section, key) {
  var v = readTomlValue(tomlText, section, key)
  return v !== null ? parseFloat(v) : null
}

function readTomlInt(tomlText, section, key) {
  var v = readTomlValue(tomlText, section, key)
  return v !== null ? parseInt(v, 10) : null
}

// ---- Config model ----
//
// IMPORTANT invariant: for every boolean whose DEFAULT is true, the reader
// must use `!== "false"` (absent key => stays true). Using `=== "true"` here
// silently disabled colorSync/linearFall/reflect for any config that did not
// explicitly carry the key — the "theme palette ignored" bug. Keep the
// DEFAULT_TRUE_BOOLS invariant in sync with tests/modelstore.test.cjs.

function readConfigFromText(tomlText) {
  var d = defaultConfig()
  if (!tomlText) return d
  d.sensitivity = readTomlFloat(tomlText, "audio", "sensitivity") ?? d.sensitivity
  if (d.sensitivity !== d.sensitivity || d.sensitivity < 0.1) d.sensitivity = 1.0
  if (d.sensitivity > 4) d.sensitivity = 4
  d.bands = readTomlInt(tomlText, "audio", "bands") ?? d.bands
  if (d.bands !== d.bands || d.bands < 4) d.bands = 32
  if (d.bands > 512) d.bands = 512
  d.gap = parseFloat(readTomlValue(tomlText, "mini", "gap") ?? "NaN")
  if (d.gap !== d.gap || d.gap < 0) d.gap = 1   // NaN/negative -> default 1
  d.widthScale = parseFloat(readTomlValue(tomlText, "mini", "width_scale") ?? "1.5")
  if (d.widthScale !== d.widthScale || d.widthScale < 0.5 || d.widthScale > 4) d.widthScale = 1.5
  d.desktopActive = readTomlValue(tomlText, "desktop", "active") === "true"
  d.enabled = readTomlValue(tomlText, "desktop", "enabled") !== "false"
  // Heartbeat lease (epoch ms, written by the open desktop window every 2s).
  // Guards against a stranded active=true with no live window.
  d.desktopHeartbeat = parseInt(readTomlValue(tomlText, "desktop", "heartbeat") ?? "0", 10)
  if (d.desktopHeartbeat !== d.desktopHeartbeat) d.desktopHeartbeat = 0
  // Color sync: default ON so the theme gradient (themeBottom->themeTop)
  // works out of the box. An ABSENT key must not disable it.
  d.colorSync = readTomlValue(tomlText, "mini", "color_sync") !== "false"
  // Theme gradient defaults: accent -> amber. Replaced the old cyan/purple
  // pair which did NOT match the active theme.
  d.themeBottom = readTomlValue(tomlText, "desktop", "theme_bottom") || "#e68e0d"
  d.themeTop = readTomlValue(tomlText, "desktop", "theme_top") || "#f59e0b"
  // Live theme accent snapshot (written by the bar on theme switches so the
  // standalone desktop window can follow themes without qs.*).
  d.themeAccent = readTomlValue(tomlText, "desktop", "theme_accent") || "#f59e0b"
  if (!isHexColor(d.themeAccent)) d.themeAccent = "#f59e0b"
  d.fireColorFrom = readTomlValue(tomlText, "desktop", "fire_color_from") || "#be1400"
  d.fireColorTo = readTomlValue(tomlText, "desktop", "fire_color_to") || "#fde047"
  if (!isHexColor(d.fireColorFrom)) d.fireColorFrom = "#be1400"
  if (!isHexColor(d.fireColorTo)) d.fireColorTo = "#fde047"
  d.fire = readTomlValue(tomlText, "desktop", "fire") === "true"
  d.peaks = readTomlValue(tomlText, "desktop", "peaks") !== "false"
  d.peakFalloff = readTomlFloat(tomlText, "desktop", "peak_falloff") ?? 0.1
  if (d.peakFalloff !== d.peakFalloff || d.peakFalloff < 0) d.peakFalloff = 0
  if (d.peakFalloff > 1) d.peakFalloff = 1
  // Peak sustain hold (ms): how long a cap waits at its high-water mark
  // before it starts to fall. 0 = fall immediately.
  d.peakSustainMs = readTomlFloat(tomlText, "desktop", "peak_sustain_ms") ?? 100
  if (d.peakSustainMs !== d.peakSustainMs || d.peakSustainMs < 0) d.peakSustainMs = 0
  if (d.peakSustainMs > 1000) d.peakSustainMs = 1000
  d.spikes = readTomlValue(tomlText, "desktop", "spikes") === "true"
  // "Stacks" UI label, canonical key "stacks"; legacy "splits" migrates.
  var stacks = readTomlValue(tomlText, "desktop", "stacks")
  d.stacks = (stacks !== null ? stacks : readTomlValue(tomlText, "desktop", "splits")) === "true"
  d.mono = readTomlValue(tomlText, "desktop", "mono") === "true"
  d.linearFall = readTomlValue(tomlText, "desktop", "linear_fall") !== "false"
  d.scope = readTomlValue(tomlText, "desktop", "scope") === "true"
  var visual = readTomlValue(tomlText, "desktop", "visual")
  d.visual = visual === "Oscilloscope" || visual === "Wave" ? "Waves"
    : ["Bars", "Waves", "Strings", "Siri"].indexOf(visual) >= 0
    ? visual : (d.scope ? "Waves" : "Bars")
  // artwork_mode RETIRED (merged into Spectrum + Artwork-backdrop toggle): an
  // old artwork_mode=true means "spectrum bars with the backdrop on". The key
  // stays READABLE so old configs migrate, but it is never written again and
  // no `artMode` state is exported (the renderer reads `artwork` only).
  var _artModeRetired = readTomlValue(tomlText, "desktop", "artwork_mode") === "true"
    || readTomlValue(tomlText, "desktop", "immersive") === "true"   // pre-rename key
  // Bar color: off = theme dominant colors, on = custom From->To tones.
  // Invalid values fall back to the theme pair (never break rendering).
  d.barColorCustom = readTomlValue(tomlText, "desktop", "bar_color_custom") === "true"
  d.barColorFrom = readTomlValue(tomlText, "desktop", "bar_color_from") || "#e68e0d"
  d.artworkColors = readTomlValue(tomlText, "desktop", "artwork_colors") === "true"
  d.barColorMiddleEnabled = readTomlValue(tomlText, "desktop", "bar_color_middle_enabled") === "true"
  d.barColorMiddle = readTomlValue(tomlText, "desktop", "bar_color_middle") || "#a855f7"
  d.barColorTo = readTomlValue(tomlText, "desktop", "bar_color_to") || "#f59e0b"
  if (!isHexColor(d.barColorFrom)) d.barColorFrom = "#e68e0d"
  if (!isHexColor(d.barColorTo)) d.barColorTo = "#f59e0b"
  // Bar gradient direction: "vertical" (default, bottom -> top) or
  // "horizontal" (left -> right across the bar field).
  d.barGradientDir = readTomlValue(tomlText, "desktop", "bar_gradient_dir") === "horizontal" ? "horizontal" : "vertical"
  d.gpu = readTomlValue(tomlText, "desktop", "gpu") !== "false"
  // Artwork backdrop: OFF by default (fresh installs), so an ABSENT key must
  // mean false — matching defaultConfig(). Using `!== "false"` here silently
  // turned the backdrop ON for every config that predates the key.
  d.artwork = readTomlValue(tomlText, "desktop", "artwork") === "true"
  if (_artModeRetired && readTomlValue(tomlText, "desktop", "artwork") === null) d.artwork = true
  d.siriClassic = readTomlValue(tomlText, "desktop", "siri_classic") === "true"
  d.siriTravel = readTomlValue(tomlText, "desktop", "siri_travel") === "true"
  d.scopeThickness = readTomlFloat(tomlText, "desktop", "scope_thickness") ?? 2
  if (d.scopeThickness !== d.scopeThickness || d.scopeThickness < 1) d.scopeThickness = 1
  if (d.scopeThickness > 5) d.scopeThickness = 5
  d.dots = readTomlValue(tomlText, "desktop", "dots") !== "false"
  d.reflect = readTomlValue(tomlText, "desktop", "reflect") !== "false"
  return d
}

function defaultConfig() {
  return {
    sensitivity: 1.0,
    bands: 32,
    gap: 1,
    widthScale: 1.5,
    desktopActive: false,
    enabled: true,
    desktopHeartbeat: 0,
    colorSync: true,
    themeBottom: "#e68e0d",
    themeTop: "#f59e0b",
    fire: false, fireColorFrom: "#be1400", fireColorTo: "#fde047",
    peaks: true, peakFalloff: 0.1, peakSustainMs: 100, spikes: false, stacks: false, mono: false,
    linearFall: true, scope: false, visual: "Bars", artwork: false, scopeThickness: 2, siriTravel: false, siriClassic: false, dots: true, reflect: true,
    barColorCustom: false, barColorFrom: "#e68e0d", barColorTo: "#f59e0b",
    artworkColors: false,
    barColorMiddleEnabled: false,
    barColorMiddle: "#a855f7",
    barGradientDir: "vertical",
    themeAccent: "#f59e0b",
    gpu: true,
  }
}

// Write a single key in a TOML section. Returns the new file content.
// Conservative: updates in place, appends section/key if missing, never
// reorders or drops unrelated keys/comments.
function writeConfigKey(tomlText, section, key, value) {
  if (!tomlText) {
    // Fresh file: emit the real defaults from one source of truth, so a new
    // install starts with theme sync ON and the current physics defaults.
    tomlText = toTOML(defaultConfig())
  }
  var lines = tomlText.split("\n")
  var header = "[" + section + "]"
  var targetIdx = -1
  for (var i = 0; i < lines.length; i++) {
    if (stripTomlComment(lines[i]).trim() === header) { targetIdx = i; break }
  }

  // Values are typed: strings are always escaped, never interpreted as TOML.
  var v = typeof value === "string" ? JSON.stringify(value) : String(value)
  var entry = key + " = " + v

  if (targetIdx === -1) {
    if (lines.length && lines[lines.length - 1].trim() !== "") lines.push("")
    lines.push(header)
    lines.push(entry)
    return lines.join("\n")
  }

  var keyIdx = -1
  for (var j = targetIdx + 1; j < lines.length; j++) {
    var t = stripTomlComment(lines[j]).trim()
    if (t.startsWith("[") && t.endsWith("]")) break
    if (t.indexOf("=") >= 0 && t.split("=")[0].trim() === key) { keyIdx = j; break }
  }

  if (keyIdx !== -1) {
    lines[keyIdx] = entry
  } else {
    lines.splice(targetIdx + 1, 0, entry)
  }
  return lines.join("\n")
}

// ---- Section/property model (used by toTOML + the reactive store) ----
// [prop, section, tomlKey, kind]
var KEY_SPEC = [
  ["sensitivity", "audio", "sensitivity", "num"],
  ["bands", "audio", "bands", "int"],
  ["gap", "mini", "gap", "num"],
  ["widthScale", "mini", "width_scale", "num"],
  ["colorSync", "mini", "color_sync", "bool"],
  ["enabled", "desktop", "enabled", "bool"],
  ["desktopActive", "desktop", "active", "bool"],
  ["desktopHeartbeat", "desktop", "heartbeat", "int"],
  ["themeBottom", "desktop", "theme_bottom", "str"],
  ["themeTop", "desktop", "theme_top", "str"],
  ["themeAccent", "desktop", "theme_accent", "str"],
  ["peaks", "desktop", "peaks", "bool"],
  ["peakFalloff", "desktop", "peak_falloff", "num"],
  ["peakSustainMs", "desktop", "peak_sustain_ms", "num"],
  ["spikes", "desktop", "spikes", "bool"],
  ["stacks", "desktop", "stacks", "bool"],
  ["mono", "desktop", "mono", "bool"],
  ["linearFall", "desktop", "linear_fall", "bool"],
  ["scope", "desktop", "scope", "bool"],
  ["visual", "desktop", "visual", "str"],
  ["scopeThickness", "desktop", "scope_thickness", "num"],
  ["siriClassic", "desktop", "siri_classic", "bool"],
  ["siriTravel", "desktop", "siri_travel", "bool"],
  ["dots", "desktop", "dots", "bool"],
  ["reflect", "desktop", "reflect", "bool"],
  ["artwork", "desktop", "artwork", "bool"],
  ["fire", "desktop", "fire", "bool"],
  ["fireColorFrom", "desktop", "fire_color_from", "str"],
  ["fireColorTo", "desktop", "fire_color_to", "str"],
  ["barColorCustom", "desktop", "bar_color_custom", "bool"],
  ["barColorFrom", "desktop", "bar_color_from", "str"],
  ["artworkColors", "desktop", "artwork_colors", "bool"],
  ["barColorMiddleEnabled", "desktop", "bar_color_middle_enabled", "bool"],
  ["barColorMiddle", "desktop", "bar_color_middle", "str"],
  ["barColorTo", "desktop", "bar_color_to", "str"],
  ["barGradientDir", "desktop", "bar_gradient_dir", "str"],
  ["gpu", "desktop", "gpu", "bool"],
]
var SECTION_ORDER = ["audio", "mini", "desktop"]

function _tomlValue(v, kind) {
  if (kind === "bool") return (v === true || v === "true") ? "true" : "false"
  if (kind === "str") return JSON.stringify(String(v))
  if (kind === "int") { var n = Math.round(Number(v)); return String(n !== n ? 0 : n) }
  var f = Number(v); if (f !== f) f = 0
  return String(f)
}

// Serialize a config object to a complete TOML document (defaults order).
// Used for fresh installs and tests; incremental UI writes go through
// writeConfigKey instead so user comments/keys survive.
function toTOML(cfg) {
  var src = cfg || defaultConfig()
  var out = ""
  for (var s = 0; s < SECTION_ORDER.length; s++) {
    var sec = SECTION_ORDER[s]
    out += "[" + sec + "]\n"
    for (var i = 0; i < KEY_SPEC.length; i++) {
      var spec = KEY_SPEC[i]
      if (spec[1] !== sec) continue
      if (spec[0] === "desktopActive" || spec[0] === "desktopHeartbeat") continue // runtime, not settings
      out += spec[2] + " = " + _tomlValue(src[spec[0]], spec[3]) + "\n"
    }
    out += "\n"
  }
  return out
}

// Shared protocol boundary: ignore malformed/nonfinite samples while accepting
// old frames whose optional metadata is absent.
function decodeFrame(line) {
  try {
    var frame = JSON.parse(String(line))
    if (!frame || typeof frame !== "object") return null
    var samples = Array.isArray(frame.bands) ? frame.bands : frame.wave
    if (!Array.isArray(samples) || samples.length > 4096) return null
    for (var i = 0; i < samples.length; i++)
      if (typeof samples[i] !== "number" || !isFinite(samples[i])) return null
    if (!Array.isArray(frame.bands)) {
      var result = { wave: samples }
      if (Number.isInteger(frame.wave_serial) && frame.wave_serial >= 0 && frame.wave_serial <= 2147483647)
        result.waveSerial = frame.wave_serial
      return result
    }
    var spectrum = { bands: samples, silent: frame.silent === true,
      source: typeof frame.source === "string" ? frame.source : "" }
    if (frame.band_layout === "strings" && samples.length === 16) spectrum.bandLayout = "strings"
    if (frame.band_layout === "siri" && samples.length === 6) spectrum.bandLayout = "siri"
    return spectrum
  } catch (e) { return null }
}

// Friendly, capitalized label for an audio backend name. Used by the panel's
// read-only SOURCE line. Unknown names pass through unchanged.
function sourceLabel(name) {
  var map = {
    pipewire: "PipeWire",
    pulse: "PulseAudio",
    jack: "JACK",
    alsa: "ALSA",
    file: "File",
    gen: "Generator"
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
    decodeFrame: decodeFrame,
    engineBin: engineBin,
    readTomlValue: readTomlValue,
    readTomlTopKey: readTomlTopKey,
    readTomlFloat: readTomlFloat,
    readTomlInt: readTomlInt,
    isHexColor: isHexColor,
    readConfigFromText: readConfigFromText,
    defaultConfig: defaultConfig,
    writeConfigKey: writeConfigKey,
    toTOML: toTOML,
    sourceLabel: sourceLabel,
    isDesktopActiveFromText: isDesktopActiveFromText,
  }
}
