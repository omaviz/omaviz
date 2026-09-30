.pragma library

// ModelStore.js — shared singleton for the omaviz Omarchy plugin.
//
// Renamed from Model.js (v8.4). .pragma library makes this a SINGLETON:
// BarWidget.qml, Panel.qml and Desktop.qml import it as
// `import "ModelStore.js" as Store`, so they all share ONE instance — the
// bar's spectrum Process writes into Store.spectrumData and the panel reads
// the same object.
//
// Responsibilities
//   * paths (config.toml, engine binary)
//   * TOML read/write helpers (section-aware, conservative in-place writes)
//   * config model: defaults -> parse -> validate
//   * a small reactive store: get/set/onChanged + loadFromTOML, so settings
//     flow  UI -> store -> TOML  and  TOML -> store -> UI  through one funnel
//   * spectrum frame parsing
//
// Back-compat: every function the old Model.js exported still exists here
// (readConfigFromText, writeConfigKey, defaultConfig, parseSpectrumLine,
// isHexColor, ...) so the migration is a pure rename.

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
// Bundled engine: lives INSIDE the plugin package (no systemd, no socket,
// no ~/.local/bin). The bar widget and the detached desktop window both spawn
// this.
var pluginDir = _derivePluginDir()
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
        // Undo writeConfigKey's escaping so a value round-trips exactly.
        var _bs2 = String.fromCharCode(92) + String.fromCharCode(34)
        v = v.split(_bs2).join(String.fromCharCode(34))
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
  d.stacks = readTomlValue(tomlText, "desktop", "stacks") === "true"
    || readTomlValue(tomlText, "desktop", "splits") === "true"
  d.mono = readTomlValue(tomlText, "desktop", "mono") === "true"
  d.linearFall = readTomlValue(tomlText, "desktop", "linear_fall") !== "false"
  d.scope = readTomlValue(tomlText, "desktop", "scope") === "true"
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
  if (_artModeRetired) d.artwork = true
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
    fire: false,
    peaks: true, peakFalloff: 0.1, peakSustainMs: 100, spikes: false, stacks: false, mono: false,
    linearFall: true, scope: false, artwork: false, scopeThickness: 2, dots: true, reflect: true,
    barColorCustom: false, barColorFrom: "#e68e0d", barColorTo: "#f59e0b",
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
    if (lines[i].trim() === header) { targetIdx = i; break }
  }

  var v = String(value)
  // Quote strings defensively: an interior double-quote MUST be escaped or the
  // emitted line is invalid TOML (and the whole file then mis-parses). Already-
  // quoted inputs pass through; arrays / inline tables stay raw.
  if (typeof value === "string" && !/^[\[{]/.test(v.trim())) {
    if (/^".*"$/.test(v.trim())) {
      v = v.trim()
    } else {
      var _q = String.fromCharCode(34)   // "
      var _bs = String.fromCharCode(92)  // backslash
      v = _q + v.split(_q).join(_bs + _q) + _q
    }
  }
  var entry = key + " = " + v

  if (targetIdx === -1) {
    if (lines.length && lines[lines.length - 1].trim() !== "") lines.push("")
    lines.push(header)
    lines.push(entry)
    return lines.join("\n")
  }

  var keyIdx = -1
  for (var j = targetIdx + 1; j < lines.length; j++) {
    var t = lines[j].trim()
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
  ["scopeThickness", "desktop", "scope_thickness", "num"],
  ["dots", "desktop", "dots", "bool"],
  ["reflect", "desktop", "reflect", "bool"],
  ["artwork", "desktop", "artwork", "bool"],
  ["fire", "desktop", "fire", "bool"],
  ["barColorCustom", "desktop", "bar_color_custom", "bool"],
  ["barColorFrom", "desktop", "bar_color_from", "str"],
  ["barColorTo", "desktop", "bar_color_to", "str"],
  ["barGradientDir", "desktop", "bar_gradient_dir", "str"],
  ["gpu", "desktop", "gpu", "bool"],
]
var SECTION_ORDER = ["audio", "mini", "desktop"]

function _specFor(prop) {
  for (var i = 0; i < KEY_SPEC.length; i++) {
    if (KEY_SPEC[i][0] === prop) return KEY_SPEC[i]
  }
  return null
}

// Normalise a store path: accepts either a bare property ("peaks") or a
// dotted "section.prop" form ("desktop.peaks"); returns the bare property.
function normalizePath(path) {
  var p = String(path)
  var dot = p.lastIndexOf(".")
  if (dot >= 0) p = p.slice(dot + 1)
  return p
}

function sectionFor(prop) {
  var s = _specFor(normalizePath(prop))
  return s ? s[1] : "desktop"
}

function tomlKeyFor(prop) {
  var s = _specFor(normalizePath(prop))
  return s ? s[2] : normalizePath(prop)
}

function _tomlValue(v, kind) {
  if (kind === "bool") return (v === true || v === "true") ? "true" : "false"
  if (kind === "str") return '"' + String(v) + '"'
  if (kind === "int") { var n = Math.round(Number(v)); return String(n !== n ? 0 : n) }
  var f = Number(v); if (f !== f) f = 0
  return String(f)
}

// Serialize a config object to a complete TOML document (defaults order).
// Used for fresh installs and tests; incremental UI writes go through
// writeConfigKey instead so user comments/keys survive.
function toTOML(cfg) {
  var src = cfg || _state || defaultConfig()
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

// Validate + coerce a single property value. Returns the sanitized value.
// Unknown props pass through unchanged (forward compatible).
function validate(prop, value) {
  var p = normalizePath(prop)
  switch (p) {
    case "sensitivity": {
      var s = Number(value); if (s !== s || s < 0.1) s = 1.0; if (s > 4) s = 4; return s
    }
    case "bands": {
      var b = Math.round(Number(value)); if (b !== b || b < 4) b = 32; if (b > 512) b = 512; return b
    }
    case "gap": {
      var g = Number(value); if (g !== g || g < 0) g = 1; return g
    }
    case "widthScale": {
      var w = Number(value); if (w !== w || w < 0.5 || w > 4) w = 1.5; return w
    }
    case "peakFalloff": {
      var f = Number(value); if (f !== f || f < 0) f = 0; if (f > 1) f = 1; return f
    }
    case "peakSustainMs": {
      var m = Number(value); if (m !== m || m < 0) m = 0; if (m > 1000) m = 1000; return m
    }
    case "scopeThickness": {
      var t = Number(value); if (t !== t || t < 1) t = 1; if (t > 5) t = 5; return t
    }
    case "barColorFrom":
    case "barColorTo":
    case "themeBottom":
    case "themeTop":
    case "themeAccent":
      return isHexColor(value) ? value : null   // null => caller keeps old value
    case "barGradientDir":
      return value === "horizontal" ? "horizontal" : "vertical"
    default:
      if (typeof value === "boolean") return value
      if (value === "true") return true
      if (value === "false") return false
      return value
  }
}

// ---- Reactive store ----
// _state is the live config object. loadFromTOML REPLACES it (a fresh object)
// so QML `property var config: Store.state()` consumers see the change and
// re-evaluate their bindings; it RETURNS the new object so callers can do
// `root.config = Store.loadFromTOML(txt)` (the old Model.js returned nothing
// here, which blanked the config and killed the widget).
var _state = defaultConfig()
var _listeners = {}   // prop -> [cb];  "*" -> [cb] for every change
var revision = 0      // bumped on every state change (bind to force updates)

function state() {
  return _state
}

function get(path) {
  var p = normalizePath(path)
  return _state[p]
}

// Update one property. Returns true when the value actually changed.
// NOTE: UI reactivity flows through the TOML file (write -> FileView change
// -> loadFromTOML -> fresh state object). set() is the in-memory half used by
// the panel preview and by tests; it also bumps `revision`.
function set(path, value) {
  var p = normalizePath(path)
  var v = validate(p, value)
  if (v === null) return false          // invalid color: keep old value
  if (_state[p] === v) return false
  _state[p] = v
  revision++
  _notify(p, v)
  return true
}

function onChanged(path, cb) {
  var p = normalizePath(path)
  if (!_listeners[p]) _listeners[p] = []
  _listeners[p].push(cb)
  return _listeners[p].length - 1
}

function _notify(p, v) {
  var ls = _listeners[p]
  if (ls) { for (var i = 0; i < ls.length; i++) ls[i](v, p) }
  var all = _listeners["*"]
  if (all) { for (var j = 0; j < all.length; j++) all[j](v, p) }
}

// Parse TOML text, replace the store state, notify every listener and return
// the new state object (never undefined).
function loadFromTOML(tomlText) {
  _state = readConfigFromText(tomlText)
  // Keep the legacy shared-config view in step: the panel used to bind to
  // sharedConfig.enabled, which never changed because loadFromTOML only
  // replaced _state. That made the ON/OFF control show a stale value on the
  // first load (the "settings don't sync on first try" bug).
  sharedConfig.enabled = _state.enabled !== false
  revision++
  var all = _listeners["*"]
  if (all) { for (var j = 0; j < all.length; j++) all[j](_state, "*") }
  return _state
}

// ---- Spectrum ----

// Shared state singleton — survives BarWidget noteWrite without re-binding
// Panel's hcfg copy.
var sharedConfig = {
  enabled: true
}

// Holds the latest spectrum frame (updated by QML Process stdout).
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

// Parse a JSON line from spectrum-bridge / omaviz-engine stdout.
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
      if (data.t !== undefined) spectrumData.t = data.t
      spectrumData.seq++
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

// Write enabled flag to config TOML (QML-visible)
function writeEnabled(value, tomlText) {
  sharedConfig.enabled = value
  set("enabled", value)
  return writeConfigKey(tomlText || "", "desktop", "enabled", value ? "true" : "false")
}

function getSharedConfig() {
  return sharedConfig
}

// ---- Module exports ----
if (typeof module !== "undefined") {
  module.exports = {
    configPath: configPath,
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
    validate: validate,
    normalizePath: normalizePath,
    sectionFor: sectionFor,
    tomlKeyFor: tomlKeyFor,
    KEY_SPEC: KEY_SPEC,
    state: state,
    get: get,
    set: set,
    onChanged: onChanged,
    loadFromTOML: loadFromTOML,
    parseSpectrumLine: parseSpectrumLine,
    spectrumData: spectrumData,
    sourceLabel: sourceLabel,
    isDesktopActiveFromText: isDesktopActiveFromText,
    writeEnabled: writeEnabled,
    getSharedConfig: getSharedConfig,
    // live bindings (module-level vars) for QML consumers
    get revision() { return revision },
    get sharedConfigRef() { return sharedConfig }
  }
}
