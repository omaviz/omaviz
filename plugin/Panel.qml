import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Omaviz settings panel (v2).
// Loaded internally by BarWidget.qml via Loader. Follows the clock-plugin
// popout contract: the bar forwards opened / open() / close() / toggle() /
// popoutSwitchClosing, and injects bar / anchorItem / hostWidget / settings.
//
// Layout (top-down):
//   preview  — live visualization (Bars / Wave / Fire), updates with dropdown
//   dropdown — visualization selector (Bars / Wave / Fire)
//   knobs     — per-visualization sliders/checkboxes (declared in .toml)
//   audio     — sensitivity / smoothing
//   options    — color sync toggle
//   footer    — Reset · Detach

Panel {
  id: root
  moduleName: "org.omaviz.visualizer"
  ipcTarget: "org.omaviz.visualizer"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property bool popoutSwitchClosing: false

  readonly property var barIdentity: hostWidget || root

  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "")
  readonly property string shellImportPath: "/usr/share/omarchy/shell"

  // ---- live state mirrored from shared singleton ----
  property var config: Model.defaultConfig()
  property var visuals: []
  property var spectrumBands: []
  property bool spectrumSilent: true
  readonly property int barCount: Math.max(
    8, (root.config && root.config.bands !== undefined) ? root.config.bands : 32)
  readonly property var barModel: (function() {
    var a = []; for (var i = 0; i < root.barCount; i++) a.push(i); return a
  })()
  // Friendly display name for the active visual.
  readonly property string activeVisual: (root.config.visualMini || "equalizer")
    .replace("equalizer", "Bars").replace("wave", "Wave").replace("fire", "Fire")
  // Style display name (Classic / Fire). Fire is a style of the Bars visual.
  readonly property string activeStyle: (root.config.style || "classic") === "fire" ? "Fire" : "Classic"

  function open() { refreshState(); root.controller.show() }
  function close() { root.controller.hide() }
  function toggle() { if (root.opened) root.close(); else root.open() }
  function closeForPopoutSwitch() { root.controller.hide() }

  // ---- writable config view ----
  FileView {
    id: configWrite
    path: Model.configPath
    // Do NOT watchChanges: writeConfig() writes via setText() and updates
    // root.config itself. If this view also watched the file, its async
    // onFileChanged would re-read a stale in-memory buffer and REVERT root.config
    // to the pre-write value — which is exactly why every control needed a
    // second click to "stick". The bar widget keeps its own (watching) view.
    watchChanges: false
    printErrors: false
    onLoaded: { root.configText = text(); root.config = Model.readConfigFromText(root.configText) }
  }

  // ---- active theme colors (for theme-dominant visualization colors) ----
  FileView {
    id: themeColors
    path: "/usr/share/omarchy/themes/active/colors.toml"
    onLoaded: pushThemeColors()
    onFileChanged: pushThemeColors()
  }
  function pushThemeColors() {
    var t = themeColors.text()
    if (!t) return
    var acc = Model.readTomlTopKey(t, "accent") || "#e68e0d"
    var top = Model.readTomlTopKey(t, "bright_blue") || acc
    writeConfig("desktop", "theme_bottom", acc)
    writeConfig("desktop", "theme_top", top)
  }

  // ---- live spectrum refresh ----
  Timer {
    id: specTimer
    interval: 50
    repeat: true
    running: true
    onTriggered: {
      root.spectrumBands = Model.spectrumData.bands
      root.spectrumSilent = Model.spectrumData.silent
    }
  }

  property var visualParamValues: {}
  property var visualParams: []
  property var visualTomlCache: {}
  // Authoritative in-memory copy of the config text. Quickshell's
  // FileView.setText() does NOT update text() synchronously, so we keep our
  // own buffer and use it for all reads/writes. configWrite is only used to
  // persist to disk.
  property string configText: ""

  onHostWidgetChanged: refreshState()
  function refreshState() {
    root.config = Model.readConfigFromText(root.configText)
    root.spectrumBands = Model.spectrumData.bands
    root.spectrumSilent = Model.spectrumData.silent
    // Theme colors are pushed by pushThemeColors() (reads active theme
    // colors.toml) — not here, to avoid the pale QML Color.accent default.
    refreshVisualParamCache()
    refreshVisuals()
  }

  function refreshVisualParamCache() {
    var cache = root.visualTomlCache || {}
    var file = root.config.visualMini || "equalizer"
    var toml = cache[file] || ""
    var params = Model.visualParamsFromText(toml, file)
    // When the Fire style is active and the current visual is Bars, also show
    // the fire-specific knobs (they live under [visual.fire] in config).
    if ((root.config.style || "classic") === "fire" && file === "equalizer") {
      var fireToml = cache["fire"] || ""
      var fireParams = Model.visualParamsFromText(fireToml, "fire")
      params = params.concat(fireParams)
    }
    root.visualParams = params
    // Read saved values from the shared config (where the user's edits live).
    root.visualParamValues = Model.visualConfigValues(root.configText, params)
  }

  function refreshVisuals() { readVisuals.refresh() }

  function barValue(index) {
    var bands = root.spectrumBands
    if (!bands || bands.length === 0) return 0
    var sens = (root.config && root.config.sensitivity !== undefined) ? root.config.sensitivity : 1.0
    var bi = Math.min(bands.length - 1, Math.floor(index * bands.length / root.barCount))
    return Math.min(1, bands[bi] * sens)
  }

  function persistShell(values) {
    var entry = { id: root.moduleName }
    for (var k in root.settings) if (k !== "id") entry[k] = root.settings[k]
    for (var key in values) entry[key] = values[key]
    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function writeConfig(section, key, value) {
    var next = Model.writeConfigKey(root.configText, section, key, value)
    root.configText = next
    configWrite.setText(next)
    root.config = Model.readConfigFromText(next)
    // Push the new config straight to the bar widget (same QML process) so
    // pause / color-sync changes take effect immediately, without relying on
    // cross-FileView disk-watch propagation.
    if (root.hostWidget && "applyConfig" in root.hostWidget) root.hostWidget.applyConfig(next)
    if (section.indexOf("visual.") === 0
        && section !== "visual.equalizer"
        && section !== "visual.oscilloscope") {
      // Update only the values map (NOT visualParams) so the Repeater keeps
      // its delegates — rebuilding visualParams mid-drag caused the
      // "have to click twice" jank.
      root.visualParamValues = Model.visualConfigValues(root.configText, root.visualParams)
    }
  }

  function selectVisual(displayName) {
    // displayName is the friendly label (Bars / Oscilloscope)
    var name = (displayName === "Oscilloscope") ? "oscilloscope" : "equalizer"
    if (name === root.config.visualDesktop) return
    writeConfig("mini", "visual", name)
    writeConfig("desktop", "visual", name)
    writeConfig("full", "visual", name)
    persistShell({ visual: name })
  }

  // Winamp visualization option writers (independent sections).
  function setEqOption(key, value) { writeConfig("visual.equalizer", key, value) }
  function setScopeOption(key, value) { writeConfig("visual.oscilloscope", key, value) }

  function selectStyle(displayName) {
    var s = (displayName === "Fire") ? "fire" : "classic"
    if (s === root.config.style) return
    writeConfig("mini", "style", s)
    writeConfig("desktop", "style", s)
    persistShell({ style: s })
    refreshVisualParamCache()
  }

  function setKnob(name, value) {
    // Write to the [visual.<source>] section the param belongs to.
    var src = "equalizer"
    for (var i = 0; i < root.visualParams.length; i++) {
      if (root.visualParams[i].name === name) { src = root.visualParams[i].source || "equalizer"; break }
    }
    writeConfig("visual." + src, name, value)
  }
  function setAudio(name, value) { writeConfig("audio", name, value) }
  // Window appearance options live under [desktop] and must reach the detached
  // window live (it polls config.toml every 300ms, so a disk write is enough).
  function setWindowOption(key, value) { writeConfig("desktop", key, value) }
  function setColorSync(on) { writeConfig("mini", "color_sync", on ? "true" : "false") }

  function resetVisual() {
    var params = Model.visualParamsFromText(
      root.visualTomlCache[root.activeVisual] || "", root.activeVisual)
    for (var i = 0; i < params.length; i++)
      writeConfig("visual." + root.config.visualMini, params[i].name, params[i].default)
  }

  // Forward detach/attach to the BarWidget, which owns the launch Process.
  // (The button label toggles via the desktopActive flag below.)
  function detach() {
    if (root.hostWidget && typeof root.hostWidget.detach === "function") {
      root.hostWidget.detach()
    }
  }

  // ---- visuals enumeration ----
  Process {
    id: readVisuals
    running: false
    command: ["bash", "-c",
      "shopt -s nullglob; for f in " + Util.shellQuote(Model.visualsDir) + "/*.toml; do " +
      "printf '%s|||OMAVIZ|||%s###OMAVIZ###' \"$f\" \"$(cat \"$f\" 2>/dev/null)\"; done"]
    function refresh() { if (!running) running = true }
    stdout: StdioCollector {
      onDataChanged: function() {
        var raw = String(readVisuals.stdout.text)
        var records = raw.split("###OMAVIZ###")
        var contents = []
        for (var i = 0; i < records.length; i++) {
          var rec = records[i]
          if (!rec) continue
          var parts = rec.split("|||OMAVIZ|||")
          if (parts.length === 2 && parts[0]) {
            contents.push({ path: parts[0], text: parts[0] ? parts[1] || "" : "" })
            Model.cacheFileText(parts[0], parts[1] || "")
          }
        }
        root.visuals = Model.discoverVisualsFromText(contents)
        var tomlByName = {}
        for (var c = 0; c < contents.length; c++) {
          var p = contents[c].path || ""
          var name = p.replace(/.*\/([^/]+)\.toml$/, "$1")
          if (name) tomlByName[name] = contents[c].text || ""
        }
        root.visualTomlCache = tomlByName
        refreshVisualParamCache()
      }
    }
  }

  // ---- UI ----
  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    // Clamp WIDTH to available space (no right spill). Height grows to the
    // full content height so EVERY field (including the footer Reset/Detach)
    // is visible with no scroll. Capped only by the available screen height
    // (so it never extends past the bottom edge on short displays).
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(d) { root.switchPanel(d) }
    }

    // Plain column — no scroll. Everything renders flat.
    Column {
      id: column
      // Size to CONTENT (not fill parent), so the card's
      // contentHeight: column.implicitHeight grows to fit everything
      // (including the footer Reset/Detach). Filling parent would make
      // implicitHeight track the parent instead of the content and clip
      // the bottom fields.
      width: parent.width
      // Outer margin comes from the card's BorderSurface padding (popupPadding).
      // Controls use width: parent.width and never spill: contentWidth is clamped
      // via fittedContentWidth, so the column is always within the visible viewport.
      spacing: Style.space(10)

      // ---- live visualization preview ----
      Text {
        text: "PREVIEW"
          color: Color.foreground
          opacity: 0.6
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.letterSpacing: 1
        }
        Rectangle {
          width: parent.width
          height: Math.max(Style.space(80), parent.width * 0.3)
          radius: Style.cornerRadius
          color: Util.alpha(Color.background, 0.35)
          Loader {
            id: previewViz
            anchors.fill: parent
            anchors.margins: Style.space(6)
            // Parity: use the SAME GPU renderer as the detached window so the
            // settings preview matches what you get on screen.
            source: (root.config.gpu === false) ? "VisualCanvas.qml" : "VisualCanvasGL.qml"
          }
          Binding { when: previewViz.item; target: previewViz.item; property: "bands"; value: root.spectrumBands }
          Binding { when: previewViz.item; target: previewViz.item; property: "silent"; value: root.spectrumSilent }
          Binding { when: previewViz.item; target: previewViz.item; property: "visual"; value: root.activeVisual }
          Binding { when: previewViz.item; target: previewViz.item; property: "colorSync"; value: root.config.colorSync }
          // v7.2 window options reflected live in the preview
          Binding { when: previewViz.item; target: previewViz.item; property: "border"; value: (root.config.border !== false) }
          Binding { when: previewViz.item; target: previewViz.item; property: "render3d"; value: (root.config.render3d === true) }
          Binding { when: previewViz.item; target: previewViz.item; property: "colorSource"; value: (root.config.colorSource || "theme") }
          Binding { when: previewViz.item; target: previewViz.item; property: "customColor"; value: (root.config.customColor || "#5ec8ff") }
          Binding { when: previewViz.item; target: previewViz.item; property: "themeBottom"; value: (root.config.themeBottom || "#19e0d4") }
          Binding { when: previewViz.item; target: previewViz.item; property: "themeTop"; value: (root.config.themeTop || "#a45cff") }
          // v7.4 Winamp visualization option sets (independent)
          Binding { when: previewViz.item; target: previewViz.item; property: "eqMode"; value: (root.config.eqMode || "bars") }
          Binding { when: previewViz.item; target: previewViz.item; property: "eqColor"; value: (root.config.eqColor || "fire") }
          Binding { when: previewViz.item; target: previewViz.item; property: "eqGrid"; value: (root.config.eqGrid === true) }
          Binding { when: previewViz.item; target: previewViz.item; property: "eqPeaks"; value: (root.config.eqPeaks !== false) }
          Binding { when: previewViz.item; target: previewViz.item; property: "eqFalloff"; value: (root.config.eqFalloff ?? 0.5) }
          Binding { when: previewViz.item; target: previewViz.item; property: "eqZoom"; value: (root.config.eqZoom || "1x") }
          Binding { when: previewViz.item; target: previewViz.item; property: "eqThickness"; value: (root.config.eqThickness || 2) }
          Binding { when: previewViz.item; target: previewViz.item; property: "scopeStyle"; value: (root.config.scopeStyle || "line") }
          Binding { when: previewViz.item; target: previewViz.item; property: "scopeColor"; value: (root.config.scopeColor || "solid") }
          Binding { when: previewViz.item; target: previewViz.item; property: "scopeGrid"; value: (root.config.scopeGrid === true) }
          Binding { when: previewViz.item; target: previewViz.item; property: "scopeScan"; value: (root.config.scopeScan === true) }
          Binding { when: previewViz.item; target: previewViz.item; property: "scopeCentered"; value: (root.config.scopeCentered === true) }
          Binding { when: previewViz.item; target: previewViz.item; property: "scopeThickness"; value: (root.config.scopeThickness || 2) }
        }

        // ---- visualization dropdown ----
        Text {
          text: "VISUALIZATION"
          color: Color.foreground
          opacity: 0.6
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.letterSpacing: 1
        }
        Dropdown {
          id: vizDropdown
          width: parent.width
          value: root.activeVisual
          options: [
            { value: "Bars", label: "Bars" },
            { value: "Oscilloscope", label: "Oscilloscope" }
          ]
          onChanged: function(v) { root.selectVisual(v) }
        }

        // ---- window appearance options (v7.2) ----
        Text {
          text: "APPEARANCE"
          color: Color.foreground
          opacity: 0.6
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.letterSpacing: 1
        }
        // Border between bars (background-colored gap) vs borderless (bars touch)
        Row {
          width: parent.width; spacing: Style.space(10)
          Text { text: "Bar Border"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; width: parent.width * 0.40; verticalAlignment: Text.AlignVCenter }
          ToggleSwitch {
            width: parent.width * 0.60 - Style.space(10)
            checked: root.config.border !== false
            onToggled: function() { root.setWindowOption("border", checked ? "false" : "true") }
          }
        }
        // 3D bar extrusion
        Row {
          width: parent.width; spacing: Style.space(10)
          Text { text: "3D Bars"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; width: parent.width * 0.40; verticalAlignment: Text.AlignVCenter }
          ToggleSwitch {
            width: parent.width * 0.60 - Style.space(10)
            checked: root.config.render3d === true
            onToggled: function() { root.setWindowOption("render3d", checked ? "false" : "true") }
          }
        }
        // Color source: sync from Omarchy theme, or a custom preset color
        Row {
          width: parent.width; spacing: Style.space(10)
          Text { text: "Color"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; width: parent.width * 0.40; verticalAlignment: Text.AlignVCenter }
          Dropdown {
            width: parent.width * 0.60 - Style.space(10)
            value: (root.config.colorSource === "custom") ? (root.config.customColor || "Custom") : "Theme"
            options: [
              { value: "Theme", label: "Theme" },
              { value: "#5ec8ff", label: "Blue" },
              { value: "#a45cff", label: "Purple" },
              { value: "#ff5cb0", label: "Pink" },
              { value: "#ff8c1a", label: "Orange" },
              { value: "#3ddc84", label: "Green" },
              { value: "#ff4d4d", label: "Red" },
              { value: "#19e0d4", label: "Cyan" }
            ]
            onChanged: function(v) {
              if (v === "Theme") { root.setWindowOption("color_source", "theme") }
              else { root.setWindowOption("color_source", "custom"); root.setWindowOption("custom_color", v) }
            }
          }
        }

        // ---- Spectrum Analyzer (Bars) options — Winamp faithful ----
        Text {
          text: "ANALYZER (BARS)"
          color: Color.foreground
          opacity: 0.6
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.letterSpacing: 1
        }
        Row { width: parent.width; spacing: Style.space(10)
          Text { text: "Mode"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; width: parent.width*0.40; verticalAlignment: Text.AlignVCenter }
          Dropdown { width: parent.width*0.60 - Style.space(10); value: (root.config.eqMode || "bars"); options: [ {value:"bars",label:"Bars"}, {value:"lines",label:"Lines"} ]; onChanged: function(v){ root.setEqOption("mode", v) } }
        }
        Row { width: parent.width; spacing: Style.space(10)
          Text { text: "Color"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; width: parent.width*0.40; verticalAlignment: Text.AlignVCenter }
          Dropdown { width: parent.width*0.60 - Style.space(10); value: (root.config.eqColor || "fire"); options: [ {value:"solid",label:"Solid"}, {value:"line",label:"Line"}, {value:"fade",label:"Fade Blocks"}, {value:"fire",label:"Fire"} ]; onChanged: function(v){ root.setEqOption("color", v) } }
        }
        Row { width: parent.width; spacing: Style.space(10)
          Text { text: "Grid"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; width: parent.width*0.40; verticalAlignment: Text.AlignVCenter }
          ToggleSwitch { width: parent.width*0.60 - Style.space(10); checked: (root.config.eqGrid === true); onToggled: function(){ root.setEqOption("grid", checked ? "true":"false") } }
        }
        Row { width: parent.width; spacing: Style.space(10)
          Text { text: "Peaks"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; width: parent.width*0.40; verticalAlignment: Text.AlignVCenter }
          ToggleSwitch { width: parent.width*0.60 - Style.space(10); checked: (root.config.eqPeaks !== false); onToggled: function(){ root.setEqOption("peaks", checked ? "true":"false") } }
        }
        Row { width: parent.width; spacing: Style.space(10)
          Text { text: "Falloff"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; width: parent.width*0.40; verticalAlignment: Text.AlignVCenter }
          PanelSlider { width: parent.width*0.60 - Style.space(10); value: (root.config.eqFalloff ?? 0.5); minimum: 0.0; maximum: 1.0; step: 0.05; onMoved: function(v){ root.setEqOption("falloff", v) } }
        }
        Row { width: parent.width; spacing: Style.space(10)
          Text { text: "Zoom"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; width: parent.width*0.40; verticalAlignment: Text.AlignVCenter }
          Dropdown { width: parent.width*0.60 - Style.space(10); value: (root.config.eqZoom || "1x"); options: [ {value:"1x",label:"1x"}, {value:"2x",label:"2x"}, {value:"4x",label:"4x"} ]; onChanged: function(v){ root.setEqOption("zoom", v) } }
        }
        Row { width: parent.width; spacing: Style.space(10)
          Text { text: "Thickness"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; width: parent.width*0.40; verticalAlignment: Text.AlignVCenter }
          Dropdown { width: parent.width*0.60 - Style.space(10); value: String(root.config.eqThickness || 2); options: [ {value:"1",label:"1"}, {value:"2",label:"2"}, {value:"3",label:"3"}, {value:"4",label:"4"} ]; onChanged: function(v){ root.setEqOption("thickness", parseInt(v,10)) } }
        }

        // ---- Oscilloscope options — Winamp faithful ----
        Text {
          text: "OSCILLOSCOPE"
          color: Color.foreground
          opacity: 0.6
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.letterSpacing: 1
        }
        Row { width: parent.width; spacing: Style.space(10)
          Text { text: "Style"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; width: parent.width*0.40; verticalAlignment: Text.AlignVCenter }
          Dropdown { width: parent.width*0.60 - Style.space(10); value: (root.config.scopeStyle || "line"); options: [ {value:"line",label:"Line"}, {value:"dot",label:"Dot"} ]; onChanged: function(v){ root.setScopeOption("style", v) } }
        }
        Row { width: parent.width; spacing: Style.space(10)
          Text { text: "Color"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; width: parent.width*0.40; verticalAlignment: Text.AlignVCenter }
          Dropdown { width: parent.width*0.60 - Style.space(10); value: (root.config.scopeColor || "solid"); options: [ {value:"solid",label:"Solid"}, {value:"line",label:"Line"}, {value:"fade",label:"Fade Blocks"}, {value:"fire",label:"Fire"} ]; onChanged: function(v){ root.setScopeOption("color", v) } }
        }
        Row { width: parent.width; spacing: Style.space(10)
          Text { text: "Grid"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; width: parent.width*0.40; verticalAlignment: Text.AlignVCenter }
          ToggleSwitch { width: parent.width*0.60 - Style.space(10); checked: (root.config.scopeGrid === true); onToggled: function(){ root.setScopeOption("grid", checked ? "true":"false") } }
        }
        Row { width: parent.width; spacing: Style.space(10)
          Text { text: "Scan"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; width: parent.width*0.40; verticalAlignment: Text.AlignVCenter }
          ToggleSwitch { width: parent.width*0.60 - Style.space(10); checked: (root.config.scopeScan === true); onToggled: function(){ root.setScopeOption("scan", checked ? "true":"false") } }
        }
        Row { width: parent.width; spacing: Style.space(10)
          Text { text: "Centered"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; width: parent.width*0.40; verticalAlignment: Text.AlignVCenter }
          ToggleSwitch { width: parent.width*0.60 - Style.space(10); checked: (root.config.scopeCentered === true); onToggled: function(){ root.setScopeOption("centered", checked ? "true":"false") } }
        }
        Row { width: parent.width; spacing: Style.space(10)
          Text { text: "Thickness"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; width: parent.width*0.40; verticalAlignment: Text.AlignVCenter }
          Dropdown { width: parent.width*0.60 - Style.space(10); value: String(root.config.scopeThickness || 2); options: [ {value:"1",label:"1"}, {value:"2",label:"2"}, {value:"3",label:"3"}, {value:"4",label:"4"} ]; onChanged: function(v){ root.setScopeOption("thickness", parseInt(v,10)) } }
        }

        // ---- audio ----
        Text {
          text: "AUDIO"
          color: Color.foreground
          opacity: 0.6
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.letterSpacing: 1
        }
        Row {
          width: parent.width; spacing: Style.space(10)
          Text { text: "Sensitivity"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; width: parent.width * 0.42; verticalAlignment: Text.AlignVCenter }
          PanelSlider { width: parent.width * 0.58 - Style.space(10); value: root.config.sensitivity; minimum: 0.1; maximum: 3.0; step: 0.05; onMoved: function(v) { root.setAudio("sensitivity", v) } }
        }
        Row {
          width: parent.width; spacing: Style.space(10)
          Text { text: "Smoothing"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; width: parent.width * 0.42; verticalAlignment: Text.AlignVCenter }
          PanelSlider { width: parent.width * 0.58 - Style.space(10); value: root.config.smoothing; minimum: 0.0; maximum: 1.0; step: 0.05; onMoved: function(v) { root.setAudio("smoothing", v) } }
        }
        // ---- options: color sync (#8) ----
        Text {
          text: "OPTIONS"
          color: Color.foreground
          opacity: 0.6
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.letterSpacing: 1
        }
        Row {
          width: parent.width; spacing: Style.space(10)
          Text { text: "Color sync (mini)"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; width: parent.width * 0.42; verticalAlignment: Text.AlignVCenter }
          ToggleSwitch {
            width: parent.width * 0.58 - Style.space(10)
            checked: root.config.colorSync
            onToggled: root.setColorSync(checked)
          }
        }

        // ---- footer ----
        Row {
          width: parent.width; spacing: Style.space(8)
          Button { id: resetBtn; text: "↺ Reset"; leftAlign: true; onClicked: root.resetVisual() }
          Item { width: parent.width - resetBtn.width - detachBtn.width - Style.space(8); height: 1 }
          Button {
            id: detachBtn
            // Read detach state from the BarWidget (source of truth), not the
            // panel's own mirrored config, so the label flips immediately.
            text: (root.hostWidget && root.hostWidget.config && root.hostWidget.config.desktopActive)
              ? "Attach ↗" : "Detach ↗"
            leftAlign: true
            onClicked: root.detach()
          }
        }
      }
    }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }
}
