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
//   top    — live visualization preview (same bars as the bar widget)
//   dropdown — visualization selector (lists ALL visualizations in visuals/)
//   knobs    — per-visualization sliders/checkboxes (declared in .toml)
//   audio    — sensitivity / smoothing
//   footer   — Reset visualization · Detach

Panel {
  id: root
  moduleName: "org.omaviz.visualizer"
  ipcTarget: "org.omaviz.visualizer"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property bool popoutSwitchClosing: false

  readonly property var barIdentity: hostWidget || root

  // Absolute path to this plugin dir (where Desktop.qml lives), used by
  // detach() to launch a standalone Quickshell window.
  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "")
  // Shell QML import root (contains the qs.Commons / qs.Ui modules). Passed to
  // the detached window via QML2_IMPORT_PATH so it can resolve shell modules.
  readonly property string shellImportPath: "/usr/share/omarchy/shell"

  // ---- live state mirrored from shared singleton ----
  property var config: Model.defaultConfig()
  property var visuals: []
  property var spectrumBands: []
  property bool spectrumSilent: true
  readonly property int barCount: Math.max(
    8, (root.config && root.config.bands !== undefined) ? root.config.bands : 32)
  readonly property var barModel: (function() {
    var a = []
    for (var i = 0; i < root.barCount; i++) a.push(i)
    return a
  })()

  function open() {
    refreshState()
    root.controller.show()
  }
  function close() {
    root.controller.hide()
  }
  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }
  function closeForPopoutSwitch() { root.controller.hide() }

  // current visualization name (shared across modes in v2)
  readonly property string activeVisual: root.config.visualMini || "equalizer"

  // ---- writable config view (the daemon + we both write here) ----
  FileView {
    id: configWrite
    path: Model.configPath
    watchChanges: true
    printErrors: false
    onLoaded: root.config = Model.readConfigFromText(text())
    onFileChanged: root.config = Model.readConfigFromText(text())
  }

  // ---- live spectrum refresh ----
  // Model.spectrumData is a JS singleton with no QML signal, so poll it on a
  // timer to drive the live preview/bar animation.
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

  // In-memory cache of the active visual's param values. Populated on open
  // and after each write — never read live from configWrite.text() inside a
  // binding (that re-enters the writable FileView and stack-overflows).
  property var visualParamValues: {}
  // Declarations (name/label/min/max/type) for the active visual's knobs,
  // populated from the cached .toml so the knobs Repeater is reliable.
  property var visualParams: []
  // Raw .toml text per visual name, populated by the enumeration Process
  // (avoids an unreliable file-text cache read inside refreshState timing).
  property var visualTomlCache: {}

  onHostWidgetChanged: refreshState()
  Component.onCompleted: refreshState()
  function refreshState() {
    root.config = Model.readConfigFromText(configWrite.text())
    root.spectrumBands = Model.spectrumData.bands
    root.spectrumSilent = Model.spectrumData.silent
    refreshVisualParamCache()
    refreshVisuals()
  }

  // Re-read the active visual's .toml param values into visualParamValues.
  function refreshVisualParamCache() {
    var cache = root.visualTomlCache || {}
    var toml = cache[root.activeVisual] || ""
    var params = Model.visualParamsFromText(toml, root.activeVisual)
    root.visualParams = params
    root.visualParamValues = Model.visualConfigValues(toml, root.activeVisual, params)
  }

  // Enumerate visualizations from visuals/ (re-scan so new files appear).
  function refreshVisuals() {
    readVisuals.refresh()
  }

  // Map a bar index to its spectrum value (root scope so the Repeater
  // delegate can resolve it during initialization).
  function barValue(index) {
    var bands = root.spectrumBands
    if (!bands || bands.length === 0) return 0
    var sens = (root.config && root.config.sensitivity !== undefined) ? root.config.sensitivity : 1.0
    var bi = Math.min(bands.length - 1, Math.floor(index * bands.length / root.barCount))
    return Math.min(1, bands[bi] * sens)
  }

  // ---- persistence ----
  function persistShell(values) {
    var entry = { id: root.moduleName }
    for (var k in root.settings) if (k !== "id") entry[k] = root.settings[k]
    for (var key in values) entry[key] = values[key]
    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // write one key to config.toml on disk, then re-read into root.config
  function writeConfig(section, key, value) {
    var next = Model.writeConfigKey(configWrite.text(), section, key, value)
    configWrite.setText(next)
    root.config = Model.readConfigFromText(next)
    if (section.indexOf("visual.") === 0) refreshVisualParamCache()
  }

  function selectVisual(name) {
    if (!name || name === root.activeVisual) return
    writeConfig("mini", "visual", name)
    writeConfig("desktop", "visual", name)
    writeConfig("full", "visual", name)
    persistShell({ visual: name })
    refreshVisualParamCache()
  }

  function setKnob(name, value) {
    writeConfig("visual." + root.activeVisual, name, value)
  }

  function setAudio(name, value) {
    writeConfig("audio", name, value)
  }

  function resetVisual() {
    var params = Model.visualParamsFromText(
      Model.readFileText(Model.visualsDir + "/" + root.activeVisual + ".toml"),
      root.activeVisual)
    for (var i = 0; i < params.length; i++) {
      writeConfig("visual." + root.activeVisual, params[i].name, params[i].default)
    }
  }

  function detach() {
    // Launch the detached desktop window (standalone Quickshell, 400x200).
    // QML2_IMPORT_PATH lets the standalone config resolve qs.Commons/qs.Ui
    // if it ever needs them; Desktop.qml is self-contained regardless.
    var desktopPath = root.pluginDir + "/Desktop.qml"
    detachProc.command = [
      "env", "QML2_IMPORT_PATH=" + root.shellImportPath,
      "quickshell", "-p", desktopPath
    ]
    detachProc.running = true
    writeConfig("desktop", "active", "true")
    persistShell({ desktopActive: true })
    root.close()
  }

  // ---- visuals enumeration (reads ALL *.toml in visuals/) ----
  // Plaintext sentinel delimiters (NUL bytes don't survive this bash's
  // printf, so we use unambiguous sentinels instead).
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
        // Map visual name -> raw toml text for reliable knob rendering.
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

  // Detach window launcher (kept alive briefly; quickshell owns the process)
  Process { id: detachProc; running: false }

  // ---- UI ----
  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(scroll.contentHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(d) { root.switchPanel(d) }
    }

    Flickable {
      id: scroll
      anchors.fill: parent
      contentWidth: column.width
      contentHeight: column.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      Column {
        id: column
        width: scroll.width
        spacing: Style.space(12)
        padding: Style.space(12)

      // ---- live visualization preview ----
      Item {
        width: parent.width
        height: Math.max(Style.space(70), parent.width * 0.28)

        Rectangle {
          anchors.fill: parent
          radius: Style.cornerRadius
          color: Util.alpha(Color.background, 0.4)
        }

        Row {
          anchors.fill: parent
          anchors.margins: Style.space(6)
          spacing: 2

          Repeater {
            model: root.barModel
            Rectangle {
              readonly property real value: barValue(modelData)
              width: (parent.width - 2 * (root.barCount - 1)) / root.barCount
              height: parent.height * value
              y: parent.height - height
              radius: 2
              color: root.spectrumSilent || root.spectrumBands.length === 0
                ? Util.alpha(Color.foreground, 0.12)
                : Util.alpha(Color.foreground, 0.3 + Math.min(1, value) * 0.7)
              Behavior on height { NumberAnimation { duration: 70; easing.type: Easing.OutCubic } }
            }
          }
        }
      }

      // ---- visualization dropdown (lists ALL visualizations) ----
      Dropdown {
        id: vizDropdown
        width: parent.width
        label: "Visualization"
        value: root.activeVisual
        options: root.visuals.map(function(v) { return { value: v.name, label: v.label } })
        onChanged: function(v) { root.selectVisual(v) }
      }

      // ---- per-visualization knobs (dynamic) ----
      Text {
        text: "OPTIONS"
        color: Color.foreground
        opacity: 0.6
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        font.letterSpacing: 1
      }

      Repeater {
        model: root.visualParams

        Row {
          width: parent.width
          height: knobCtrl.implicitHeight
          spacing: Style.space(8)
          Text {
            text: modelData.label
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            width: parent.width * 0.4
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
          }
          Loader {
            id: knobCtrl
            width: parent.width * 0.6
            sourceComponent: modelData.type === "boolean" ? boolComp : sliderComp
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
      Text {
        text: "AUDIO"
        color: Color.foreground
        opacity: 0.6
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        font.letterSpacing: 1
      }

      Row {
        width: parent.width
        spacing: Style.space(8)
        Text { text: "Sensitivity"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; width: parent.width * 0.4; verticalAlignment: Text.AlignVCenter }
        PanelSlider {
          width: parent.width * 0.6
          value: root.config.sensitivity
          minimum: 0.1; maximum: 3.0; step: 0.05
          onMoved: function(v) { root.setAudio("sensitivity", v) }
        }
      }
      Row {
        width: parent.width
        spacing: Style.space(8)
        Text { text: "Smoothing"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; width: parent.width * 0.4; verticalAlignment: Text.AlignVCenter }
        PanelSlider {
          width: parent.width * 0.6
          value: root.config.smoothing
          minimum: 0.0; maximum: 1.0; step: 0.05
          onMoved: function(v) { root.setAudio("smoothing", v) }
        }
      }

      // ---- footer ----
      Row {
        width: parent.width
        spacing: Style.space(8)
        Button {
          id: resetBtn
          text: "↺ Reset"
          leftAlign: true
          onClicked: root.resetVisual()
        }
        Item { width: parent.width - resetBtn.width - detachBtn.width - Style.space(8); height: 1 }
        Button {
          id: detachBtn
          text: "Detach ↗"
          onClicked: root.detach()
        }
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
