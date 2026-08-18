import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Omaviz settings panel (v7.2 / TASK #2).
//
// Bar-widget contract (verified against live BarWidget.qml):
//   injectPanel() sets:  t.bar, t.anchorItem, t.hostWidget, t.settings
//   the widget reads:    panelLoader.item.opened / open() / close() / toggle()
//
// We build on the shared `Panel` base (qs.Ui/Panel.qml) which owns the
// PanelController show/hide lifecycle, so opened/open/close/toggle resolve to
// the controller's open state — exactly what BarWidget.qml expects. The
// KeyboardPanel renders the popup surface (anchorItem + owner + open: root.opened).
// manageIpc is false so the panel does NOT register a second IpcHandler for the
// same target (BarWidget already owns it).
//
// Left-click on the bar button -> root.toggle() -> controller show/hide.
// Everything here is GPU-free: the panel never launches a window. The preview
// uses the Canvas-2D VisualCanvas (not the GL ShaderEffect) so it is safe to
// load inside the bar process.

Panel {
  id: root
  moduleName: "org.omaviz.visualizer"
  ipcTarget: "org.omaviz.visualizer"
  manageIpc: false

  // ---- Injected by BarWidget.injectPanel() ----
  property var anchorItem: null
  property var hostWidget: null
  // `bar` and `settings` are provided by the Panel base and overwritten by
  // injectPanel(); declared here so the base binding does not error pre-injection.

  // ---- In-memory config buffer (synchronous round-trip) ----
  // Quickshell FileView.setText() does NOT update text() synchronously, so the
  // panel keeps its own buffer and writes through Model.writeConfigKey, then
  // re-parses the same string so the first click always sticks (regression
  // guard: "every control needs two clicks").
  property string cfgText: configFile.text()

  // Live config object (mirrors BarWidget's `root.config`). The preview binds
  // to this so it re-renders on every write; it MUST exist or the bindings
  // throw "Cannot read property of undefined".
  property var config: Model.readConfigFromText(cfgText)

  function reloadCfg() { cfgText = configFile.text(); root.config = Model.readConfigFromText(cfgText) }
  function commit(key, value, section) {
    cfgText = Model.writeConfigKey(cfgText, section || "desktop", key, value)
    configFile.setText(cfgText)
    root.config = Model.readConfigFromText(cfgText)
    if (hostWidget && typeof hostWidget.applyConfig === "function")
      hostWidget.applyConfig(cfgText)
  }
  function readCfg(key, section) {
    return Model.readTomlValue(cfgText, section || "desktop", key)
  }
  function cfgBool(key, section) {
    return readCfg(key, section) === "true"
  }

  // ---- Popup lifecycle (consumed by BarWidget) ----
  readonly property bool opened: panel.open
  function open() { panel.open = true }
  function close() { panel.open = false }
  function toggle() { panel.open = !panel.open }

  // ---- Live preview of the selected mini visual (Canvas-2D, GPU-free) ----
  function currentViz() {
    return (root.readCfg("visual", "mini") || "equalizer") === "oscilloscope" ? "Wave" : "Bars"
  }
  function currentStyle() {
    return (root.readCfg("style", "mini") || "classic") === "fire" ? "Fire" : "Classic"
  }

  // ---- Source (read-only, from the engine's stdout) ----
  readonly property string sourceLabelText:
    Model.sourceLabel(Model.spectrumData.source || "")

  // ---- Detach/Attach label derived from desktop.active (source of truth) ----
  readonly property bool detached: root.cfgBool("active", "desktop")
  function toggleDetach() {
    if (hostWidget && typeof hostWidget.detach === "function") hostWidget.detach()
    // The flag flips in the config file (hostWidget writes desktop.active +
    // reset); reload so our label follows immediately.
    Qt.callLater(root.reloadCfg)
  }

  function resetAll() {
    // Reset to defaults (Matte Black-aligned). Writes a clean audio+mini+desktop
    // block; visuals keep their own sections untouched.
    var base = "[audio]\nsensitivity = 1.0\nsmoothing = 0.5\nbands = 32\n\n" +
      "[mini]\nvisual = \"equalizer\"\nstyle = \"classic\"\ncolor_sync = false\n\n" +
      "[desktop]\nactive = \"false\"\ngpu = \"true\"\ncolor_source = \"theme\"\n" +
      "custom_color = \"#5ec8ff\"\ntheme_bottom = \"#e68e0d\"\ntheme_top = \"#f59e0b\"\n" +
      "fire = \"false\"\n"
    cfgText = base
    configFile.setText(cfgText)
    root.config = Model.readConfigFromText(cfgText)
    if (hostWidget && typeof hostWidget.applyConfig === "function")
      hostWidget.applyConfig(cfgText)
  }

  // surface
  KeyboardPanel {
    id: panel
    anchors.fill: parent
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(720))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onActivateRequested: root.close()
    }

    ScrollView {
      anchors.fill: parent
      contentWidth: column.implicitWidth
      contentHeight: column.implicitHeight
      clip: true

      Column {
        id: column
        width: panel.contentWidth
        spacing: Style.space(10)
        padding: Style.space(14)

        // ---- Live preview ----
        PanelSectionHeader { text: "PREVIEW" }
        Rectangle {
          width: parent.width; height: Style.space(60)
          color: Color.popups.background
          radius: Style.cornerRadius
          border.width: 1; border.color: Qt.rgba(1,1,1,0.08)
          VisualCanvas {
            id: previewViz
            anchors.fill: parent; anchors.margins: Style.space(6)
            bands: Model.spectrumData.bands
            silent: Model.spectrumData.silent
            visual: root.currentViz()
            style: root.currentStyle()
            colorSync: root.config.colorSync
            barCount: 32
            colourScheme: 0
          }
        }
        // v7.2 window options reflected live in the preview
        Binding { when: previewViz.item; target: previewViz.item; property: "border"; value: (root.config.border !== false) }
        Binding { when: previewViz.item; target: previewViz.item; property: "colorSource"; value: (root.config.colorSource || "theme") }
        Binding { when: previewViz.item; target: previewViz.item; property: "customColor"; value: (root.config.customColor || "#5ec8ff") }
        Binding { when: previewViz.item; target: previewViz.item; property: "themeBottom"; value: (root.config.themeBottom || "#e68e0d") }
        Binding { when: previewViz.item; target: previewViz.item; property: "themeTop"; value: (root.config.themeTop || "#f59e0b") }
        // TASK #2: fire toggle drives the winamp-flame preview too
        Binding { when: previewViz.item; target: previewViz.item; property: "fire"; value: (root.config.fire === true) }
        Binding { when: previewViz.item; target: previewViz.item; property: "peaks"; value: (root.config.peaks !== false) }
        Binding { when: previewViz.item; target: previewViz.item; property: "falloff"; value: (root.config.falloff ?? 0.5) }
        Binding { when: previewViz.item; target: previewViz.item; property: "alpha"; value: (root.config.alpha ?? 1.0) }

        PanelSeparator { }

        // ---- VISUALIZATION (Bar vs Oscilloscope; Fire is a style, not a viz) ----
        PanelSectionHeader { text: "VISUALIZATION" }
        ButtonGroup {
          id: vizGroup
          width: parent.width
          options: ["Bar", "Oscilloscope"]
          value: (root.readCfg("visual", "mini") || "equalizer") === "oscilloscope" ? "Oscilloscope" : "Bar"
          onChanged: function(v) {
            var key = v === "Oscilloscope" ? "oscilloscope" : "equalizer"
            commit("visual", '"' + key + '"', "mini")
            commit("visual", '"' + key + '"', "desktop")
          }
        }

        PanelSeparator { }

        // ---- STYLE (Canvas-2D bar style; GL path uses the Fire toggle below) ----
        PanelSectionHeader { text: "STYLE" }
        // On the GL-default render path, STYLE 'Fire' is a no-op (the winamp
        // flame is driven by the Fire toggle, which sets desktop.fire and feeds
        // the shader). STYLE 'Fire' only restyles the Canvas-2D fallback, so we
        // disable it when GPU rendering is active to avoid a misleading control.
        ButtonGroup {
          id: styleGroup
          width: parent.width
          enabled: (root.readCfg("gpu", "desktop") || "true") === "false"
          options: ["Classic", "Fire (Canvas)"]
          value: (root.readCfg("style", "mini") || "classic") === "fire" ? "Fire (Canvas)" : "Classic"
          onChanged: function(v) {
            var key = v === "Fire (Canvas)" ? "fire" : "classic"
            commit("style", '"' + key + '"', "mini")
            commit("style", '"' + key + '"', "desktop")
          }
        }
        Text {
          visible: (root.readCfg("gpu", "desktop") || "true") === "false"
          text: "Canvas-2D style only (GPU renderer uses the Fire toggle below)"
          color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
          font.family: Style.font.family; font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
          width: parent.width
        }
        // NEW (TASK #2): independent Fire toggle. Drives the winamp-flame on the
        // GL/default renderer (desktop.fire -> visual.frag fireOn()), regardless
        // of the Classic/Fire CANVAS style above.
        Row {
          width: parent.width
          spacing: Style.space(10)
          ToggleSwitch {
            id: fireToggle
            checked: root.cfgBool("fire")
            onToggled: commit("fire", checked ? "true" : "false")
          }
          Text {
            text: "Fire effect (winamp flame, GPU/GL)"
            color: root.bar ? root.bar.foreground : Color.foreground
            font.family: Style.font.family; font.pixelSize: Style.font.body
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        PanelSeparator { }

        // ---- Winamp-style controls (bar style, colors, glow) ----
        PanelSectionHeader { text: "BAR STYLE" }
        Row {
          width: parent.width
          spacing: Style.space(10)
          Text {
            text: "Bars"
            color: root.bar ? root.bar.foreground : Color.foreground
            font.family: Style.font.family; font.pixelSize: Style.font.body
            anchors.verticalCenter: parent.verticalCenter
          }
          ButtonGroup {
            id: eqModeGroup
            width: parent.width - Style.space(60)
            options: ["Bars", "Lines"]
            value: (root.readCfg("mode", "visual.equalizer") || "bars") === "lines" ? "Lines" : "Bars"
            onChanged: function(v) {
              commit("mode", '"' + (v === "Lines" ? "lines" : "bars") + '"', "visual.equalizer")
            }
          }
        }
        Row {
          width: parent.width
          spacing: Style.space(10)
          Text {
            text: "Color"
            color: root.bar ? root.bar.foreground : Color.foreground
            font.family: Style.font.family; font.pixelSize: Style.font.body
            anchors.verticalCenter: parent.verticalCenter
          }
          ButtonGroup {
            id: eqColorGroup
            width: parent.width - Style.space(60)
            options: ["Solid", "Line", "Fade", "Fire"]
            value: (function() {
              var c = root.readCfg("color", "visual.equalizer") || "fire"
              return c === "solid" ? "Solid" : c === "line" ? "Line" : c === "fade" ? "Fade" : "Fire"
            })()
            onChanged: function(v) {
              var key = v === "Solid" ? "solid" : v === "Line" ? "line" : v === "Fade" ? "fade" : "fire"
              commit("color", '"' + key + '"', "visual.equalizer")
            }
          }
        }
        Row {
          width: parent.width
          spacing: Style.space(10)
          Text {
            text: "Glow"
            color: root.bar ? root.bar.foreground : Color.foreground
            font.family: Style.font.family; font.pixelSize: Style.font.body
            anchors.verticalCenter: parent.verticalCenter
          }
          ToggleSwitch {
            id: glowToggle
            checked: root.cfgBool("peaks", "visual.equalizer")
            onToggled: commit("peaks", checked ? "true" : "false", "visual.equalizer")
          }
          Text {
            text: "Peak hold"
            color: root.bar ? root.bar.foreground : Color.foreground
            font.family: Style.font.family; font.pixelSize: Style.font.body
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        PanelSeparator { }

        // ---- OPTIONS ----
        PanelSectionHeader { text: "OPTIONS" }
        Row {
          width: parent.width
          spacing: Style.space(10)
          Text {
            text: "Color sync"
            color: root.bar ? root.bar.foreground : Color.foreground
            font.family: Style.font.family; font.pixelSize: Style.font.body
            anchors.verticalCenter: parent.verticalCenter
          }
          ToggleSwitch {
            id: colorSyncToggle
            checked: root.cfgBool("color_sync", "mini")
            onToggled: commit("color_sync", checked ? "true" : "false", "mini")
          }
        }
        Row {
          width: parent.width
          spacing: Style.space(10)
          Text {
            text: "Color source"
            color: root.bar ? root.bar.foreground : Color.foreground
            font.family: Style.font.family; font.pixelSize: Style.font.body
            anchors.verticalCenter: parent.verticalCenter
          }
          ButtonGroup {
            id: colorSrcGroup
            width: parent.width - Style.space(100)
            options: ["Theme", "Custom"]
            value: (root.readCfg("color_source", "desktop") || "theme") === "custom" ? "Custom" : "Theme"
            onChanged: function(v) {
              commit("color_source", '"' + (v === "Custom" ? "custom" : "theme") + '"', "desktop")
            }
          }
        }

        PanelSeparator { }

        // ---- AUDIO (read-only source + sensitivity/smoothing) ----
        PanelSectionHeader { text: "AUDIO" }
        Row {
          width: parent.width
          spacing: Style.space(8)
          Text {
            text: "SOURCE"
            color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
            font.family: Style.font.family; font.pixelSize: Style.font.bodySmall
            font.letterSpacing: 1
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            text: root.sourceLabelText + " · default sink"
            color: Color.accent
            font.family: Style.font.family; font.pixelSize: Style.font.body
            anchors.verticalCenter: parent.verticalCenter
          }
        }
        Row {
          width: parent.width
          spacing: Style.space(10)
          Text {
            text: "Sensitivity"
            color: root.bar ? root.bar.foreground : Color.foreground
            font.family: Style.font.family; font.pixelSize: Style.font.body
            anchors.verticalCenter: parent.verticalCenter
          }
          PanelSlider {
            width: parent.width - Style.space(110)
            minimum: 0.1; maximum: 3.0; step: 0.1
            value: parseFloat(root.readCfg("sensitivity", "audio") || "1.0")
            onMoved: function(v) { commit("sensitivity", v.toFixed(1), "audio") }
          }
        }
        Row {
          width: parent.width
          spacing: Style.space(10)
          Text {
            text: "Smoothing"
            color: root.bar ? root.bar.foreground : Color.foreground
            font.family: Style.font.family; font.pixelSize: Style.font.body
            anchors.verticalCenter: parent.verticalCenter
          }
          PanelSlider {
            width: parent.width - Style.space(110)
            minimum: 0.0; maximum: 1.0; step: 0.05
            value: parseFloat(root.readCfg("smoothing", "audio") || "0.5")
            onMoved: function(v) { commit("smoothing", v.toFixed(2), "audio") }
          }
        }

        PanelSeparator { }

        // ---- Footer: Reset + Detach/Attach ----
        Row {
          width: parent.width
          spacing: Style.space(8)
          Button {
            text: "Reset"
            onClicked: root.resetAll()
          }
          Item { width: parent.width - resetBtn.width - detachBtn.width - Style.space(8); height: 1 }
          Button {
            id: detachBtn
            text: root.detached ? "Attach ↗" : "Detach ↗"
            onClicked: root.toggleDetach()
          }
        }
      }
    }

    Component.onCompleted: configFile.reload()
  }

  // Writable config view — no watch so async reverts never clobber a click.
  FileView {
    id: configFile
    path: Model.configPath
    watchChanges: false
    printErrors: false
    onLoaded: root.reloadCfg()
    onFileChanged: root.reloadCfg()
  }
}
