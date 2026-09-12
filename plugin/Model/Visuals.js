// Model/Visuals.js — visual TOML parsing, discovery, param tagging, and
// config-value reading for visuals. Plain JS module (no pragma): imported by
// the Model.js facade under QML, loaded directly by node tests under Node.
//
// Owns ONLY the visual-discovery + param-contract concern (ADR-0003 §2 item 2):
// parseVisualToml, discoverVisualsFromText, visualParamsFromText,
// visualConfigValues, readTomlTopKey (theme colors.toml reader).

// ---- Visual TOML parsing ----

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

// ---- Visual discovery from text files ----

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

// ---- Param declaration tagging ----

// Get param declarations for a visual's .toml text
function visualParamsFromText(tomlText, name) {
  var v = parseVisualToml(tomlText, name)
  // Tag each param with the visual it belongs to, so the panel writes
  // knob edits back to the correct [visual.<name>] section.
  for (var i = 0; i < v.params.length; i++) v.params[i].source = name
  return v.params
}

// ---- Visual config-value reading ----

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

// ---- Theme top-level TOML reader (colors.toml) ----

// readTomlTopKey is defined here because it's the visual/theme TOML reader
// (reads top-level keys from a TOML doc, e.g. theme colors.toml).
//
// Under QML the facade wires this up; under Node the test compiles both
// modules in the same V8 context so the internal reference resolves.
var readTomlValue = readTomlValue || function() { return null }

function readTomlTopKey(tomlText, key) {
  return readTomlValue(tomlText, "", key)
}

// ---- Node export (test harness + any standalone consumer) ----
if (typeof module !== "undefined") {
  module.exports = {
    parseVisualToml: parseVisualToml,
    discoverVisualsFromText: discoverVisualsFromText,
    visualParamsFromText: visualParamsFromText,
    visualConfigValues: visualConfigValues,
    readTomlTopKey: readTomlTopKey
  }
}
