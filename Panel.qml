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
// Layout (top-down, no right-side list per v2 spec):
//   top 30%  — live visualization preview (same bars as the bar widget)
//   dropdown — visualization selector
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

  // ---- live spectrum: read shared singleton snapshot on open ----
  // (Model.spectrumData is a JS object with no QML signal; the bar mutates it
  // every frame. We snapshot it in refreshState() when the panel opens.)

  // In-memory cache of the active visual's param values. Populated once on
  // open and after each write — never read live from configWrite.text() inside
  // a binding, which would re-enter the writable FileView and stack-overflow.
  property var visualParamValues: {}

  onHostWidgetChanged: refreshState()
  Component.onCompleted: refreshState()
  function refreshState() {
    root.config = Model.readConfigFromText(configWrite.text())
    root.spectrumBands = Model.spectrumData.bands
    root.spectrumSilent = Model.spectrumData.silent
    refreshVisualParamCache()
    readVisuals.refresh()
  }

  // Re-read the active visual's .toml param values into visualParamValues.
  function refreshVisualParamCache() {
    var toml = Model.readFileText(Model.visualsDir + "/" + root.activeVisual + ".toml")
    var params = Model.visualParamsFromText(toml, root.activeVisual)
    root.visualParamValues = Model.visualConfigValues(toml, root.activeVisual, params)
  }

  // Map a bar index to its spectrum value (root scope so the preview
  // Repeater delegate can resolve it during initialization).
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
    // keep the in-memory visual param cache in sync (reads from disk, not
    // from the writable FileView binding path)
    if (section.indexOf("visual.") === 0) refreshVisualParamCache()
  }

  function selectVisual(name) {
    if (!name || name === root.activeVisual) return
    writeConfig("mini", "visual", name)
    writeConfig("desktop", "visual", name)
    writeConfig("full", "visual", name)
    persistShell({ visual: name })
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
    writeConfig("desktop", "active", "true")
    persistShell({ desktopActive: true })
    root.close()
  }

  // ---- visuals enumeration ----
  Process {
    id: readVisuals
    running: false
    command: ["bash", "-c",
      "for f in " + Util.shellQuote(Model.visualsDir) + "/*.toml; do " +
      "[ -f \"$f\" ] && printf '%s\\0%s\\0' \"$f\" \"$(cat \"$f\" 2>/dev/null)\"; done"]
    function refresh() { if (!running) running = true }
    stdout: SplitParser {
      onRead: function(data) {
        var chunks = String(data).split("\0")
        var contents = []
        for (var i = 0; i + 1 < chunks.length; i += 2) {
          if (chunks[i]) {
            contents.push({ path: chunks[i], text: chunks[i + 1] || "" })
            Model.cacheFileText(chunks[i], chunks[i + 1] || "")
          }
        }
        root.visuals = Model.discoverVisualsFromText(contents)
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
    contentWidth: panel.fittedContentWidth(Style.space(320))
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
        spacing: Style.space(10)
        padding: Style.space(12)

      // ---- top 30%: live preview ----
      Item {
        width: parent.width
        height: Math.max(Style.space(60), parent.width * 0.3)

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
        label: "Visualization"
        showLabel: false
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
        model: Model.visualParamsFromText(
          Model.readFileText(Model.visualsDir + "/" + root.activeVisual + ".toml"),
          root.activeVisual)

        Item {
          width: parent.width
          height: knobRow.implicitHeight
          Row {
            id: knobRow
            width: parent.width
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
              width: parent.width * 0.6
              sourceComponent: modelData.type === "boolean" ? boolComp : sliderComp
              property var param: modelData
            }
          }
        }
      }

      Component {
        id: sliderComp
        PanelSlider {
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
