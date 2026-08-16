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
    if (section.indexOf("visual.") === 0) {
      // Update only the values map (NOT visualParams) so the Repeater keeps
      // its delegates — rebuilding visualParams mid-drag caused the
      // "have to click twice" jank.
      root.visualParamValues = Model.visualConfigValues(root.configText, root.visualParams)
    }
  }

  function selectVisual(displayName) {
    // displayName is the friendly label (Bars / Wave)
    var name = displayName
    if (name === "Bars") name = "equalizer"
    else if (name === "Wave") name = "wave"
    if (name === root.config.visualMini) return
    writeConfig("mini", "visual", name)
    writeConfig("desktop", "visual", name)
    writeConfig("full", "visual", name)
    persistShell({ visual: name })
    refreshVisualParamCache()
  }

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
  function setColorSync(on) { writeConfig("mini", "color_sync", on ? "true" : "false") }

  function resetVisual() {
    var params = Model.visualParamsFromText(
      root.visualTomlCache[root.activeVisual] || "", root.activeVisual)
    for (var i = 0; i < params.length; i++)
      writeConfig("visual." + root.config.visualMini, params[i].name, params[i].default)
  }

  function detach() {
    var desktopPath = root.pluginDir + "/Desktop.qml"
    detachProc.command = [
      "env", "QML2_IMPORT_PATH=" + root.shellImportPath,
      "quickshell", "-p", desktopPath
    ]
    // Pause the mini player while the desktop window is open (#7).
    writeConfig("desktop", "active", "true")
    persistShell({ desktopActive: true })
    root.close()
    // Force a fresh start: toggle running false->true so Quickshell always
    // re-spawns the child (a bare `running = true` is a no-op if it already
    // thinks it is running). The StdioCollector above ensures running flips
    // to false when the previous window closed.
    detachProc.running = false
    Qt.callLater(function() { detachProc.running = true })
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

  // Launches the standalone desktop window. A stdout parser is REQUIRED:
  // without one the Process never sees EOF and its `running` flag stays true
  // after the child quickshell exits, so a second detach() (running=true on an
  // already-"true" process) is a no-op and no window spawns. The parser drains
  // stdout so `running` correctly flips to false on exit, allowing re-launch.
  Process {
    id: detachProc
    running: false
    // StdioCollector drains stdout so the Process sees EOF when the child
    // quickshell exits and `running` flips to false — otherwise a second
    // detach() (running=true on an already-"true" process) is a no-op.
    stdout: StdioCollector { onDataChanged: function() {} }
    onExited: function(code, status) {
      // Window closed (or launch failed). Resume the mini so it is never
      // left stuck-paused. Desktop.qml also writes active=false on close.
      if (root.config.desktopActive === true) writeConfig("desktop", "active", "false")
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
            source: "VisualCanvas.qml"
          }
          Binding { when: previewViz.item; target: previewViz.item; property: "bands"; value: root.spectrumBands }
          Binding { when: previewViz.item; target: previewViz.item; property: "silent"; value: root.spectrumSilent }
          Binding { when: previewViz.item; target: previewViz.item; property: "visual"; value: root.activeVisual }
          Binding { when: previewViz.item; target: previewViz.item; property: "style"; value: root.activeStyle }
          Binding { when: previewViz.item; target: previewViz.item; property: "colorSync"; value: root.config.colorSync }
          Binding { when: previewViz.item; target: previewViz.item; property: "barCount"; value: (root.visualParamValues.bar_count !== undefined ? root.visualParamValues.bar_count : 0) }
          Binding { when: previewViz.item; target: previewViz.item; property: "colourScheme"; value: (root.visualParamValues.colour_scheme !== undefined ? root.visualParamValues.colour_scheme : 0) }
        }

        // ---- visualization dropdown ----
        Dropdown {
          id: vizDropdown
          width: parent.width
          label: "Visualization"
          value: root.activeVisual
          // Fire is a STYLE of Bars, not a visualization — exclude it here.
          options: root.visuals
            .filter(function(v) { return v.name !== "fire" })
            .map(function(v) {
              var d = v.name
              if (d === "equalizer") d = "Bars"
              else if (d === "wave") d = "Wave"
              return { value: d, label: d }
            })
          onChanged: function(v) { root.selectVisual(v) }
        }

        // ---- style (Classic / Fire) — Fire is a style of the Bars visual ----
        Dropdown {
          id: styleDropdown
          width: parent.width
          label: "Style"
          value: root.activeStyle
          options: [
            { value: "Classic", label: "Classic" },
            { value: "Fire", label: "Fire" }
          ]
          onChanged: function(v) { root.selectStyle(v) }
        }

        // ---- per-visualization knobs ----
        Repeater {
          model: root.visualParams
          Row {
            width: parent.width
            height: Math.max(Style.space(28), knobCtrl.implicitHeight)
            spacing: Style.space(10)
            Text {
              text: modelData.label
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              width: parent.width * 0.40
              elide: Text.ElideRight
              verticalAlignment: Text.AlignVCenter
              wrapMode: Text.NoWrap
            }
            Loader {
              id: knobCtrl
              width: parent.width * 0.60 - Style.space(10)
              sourceComponent: (modelData.boolean === true) ? boolComp : sliderComp
              property var param: modelData
            }
          }
        }
        Component {
          id: sliderComp
          PanelSlider {
            width: parent ? parent.width : 100
            value: currentKnobValue(param)
            minimum: param.min
            maximum: param.max
            step: Math.max(0.001, (param.max - param.min) / 100)
            onMoved: function(v) { root.setKnob(param.name, v) }
            function currentKnobValue(p) {
              var v = root.visualParamValues[p.name]
              return v !== undefined ? v : p.default
            }
          }
        }
        Component {
          id: boolComp
          ToggleSwitch {
            width: parent ? parent.width : 100
            checked: currentBoolValue(param)
            onToggled: root.setKnob(param.name, !checked)
            function currentBoolValue(p) {
              var v = root.visualParamValues[p.name]
              return v === undefined ? (p.default === true) : (v === true)
            }
          }
        }

        // ---- audio ----
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
          Button { id: detachBtn; text: "Detach ↗"; onClicked: root.detach() }
        }
      }
    }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }
}
