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

  // ---- Popup lifecycle ----
  // IMPORTANT: do NOT override opened/open/close/toggle here. The `Panel`
  // base (qs.Ui/Panel.qml) owns a PanelController and drives the popup surface
  // through it: `opened` === panelController.open, and open()/close()/toggle()
  // call panelController.show()/hide(). The KeyboardPanel below binds its
  // `open` to `root.opened` (= panelController.open), so the show path is:
  //   BarWidget.toggle() -> panelLoader.item.toggle() -> Panel base toggle()
  //     -> panelController.show() -> panelController.open=true -> KeyboardPanel
  //        shows.
  // The earlier (broken) version overrode these to set panel.open directly,
  // which never invoked panelController.show(), so the panel never appeared.

  // ---- Live preview of the selected mini visual (Canvas-2D, GPU-free) ----
  function currentViz() {
    // reference cfgText so the preview binding re-evaluates on every commit
    var _dep = cfgText
    return (root.readCfg("visual", "mini") || "equalizer") === "oscilloscope" ? "Wave" : "Bars"
  }
  function currentStyle() {
    var _dep = cfgText
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
      "[desktop]\nactive = \"false\"\ngpu = \"true\"\ncolor_source = \"theme\"\ndensity = 128\n" +
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
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    // Fixed size captured once at open — re-fitting on every control change
    // made the dialog jump/jitter when toggles altered implicit sizes.
    property bool _sizeLocked: false
    property int _frozenH: 0
    onOpenedChanged: {
      if (opened) {
        _sizeLocked = false
        _frozenH = 0
        lockTimer.restart()
      }
    }
    Timer {
      id: lockTimer
      interval: 250   // let content lay out once, then freeze size
      onTriggered: {
        if (opened && !_sizeLocked) {
          _frozenH = contentHeight
          _sizeLocked = true
        }
      }
    }
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: _sizeLocked ? _frozenH : panel.fittedContentHeight(column.implicitHeight, Style.space(720))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onActivateRequested: root.close()
    }

    ScrollView {
      anchors.fill: parent
      contentWidth: width          // vertical scroll only — no horizontal
      contentHeight: column.implicitHeight
      clip: true

      Column {
        id: column
        x: Style.space(14)               // left padding via position
        width: panel.contentWidth - Style.space(28)  // viewport minus both paddings
        spacing: Style.space(10)

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
            // Model.spectrumData is a plain JS object — assignments don't emit
            // change signals. Poll into notified locals so the Canvas repaints.
            property var _liveBands: []
            property bool _liveSilent: true
            property string _liveVisual: "Bars"
            property string _liveStyle: "Classic"
            Timer {
              interval: 33; repeat: true; running: true
              onTriggered: {
                var nb = Model.spectrumData.bands
                previewViz._liveBands = nb
                previewViz._liveSilent = Model.spectrumData.silent
                var v = root.currentViz()
                var st = root.currentStyle()
                if (previewViz._liveVisual !== v) previewViz._liveVisual = v
                if (previewViz._liveStyle !== st) previewViz._liveStyle = st
              }
            }
            bands: previewViz._liveBands
            silent: previewViz._liveSilent
            visual: previewViz._liveVisual
            style: previewViz._liveStyle
            colorSync: root.config.colorSync
            barCount: (root.config.density || 64)   // dense preview reflects the desktop window
            colourScheme: 0
          }
        }
        // (VisualCanvas is a plain Canvas — properties bound inline above.)

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
            text: "Width"
            color: root.bar ? root.bar.foreground : Color.foreground
            font.family: Style.font.family; font.pixelSize: Style.font.body
            anchors.verticalCenter: parent.verticalCenter
          }
          PanelSlider {
            width: parent.width - Style.space(110)
            minimum: 0.5; maximum: 4; step: 0.1
            value: parseFloat(root.readCfg("width_scale", "mini") || "1.5")
            onMoved: function(v) { commit("width_scale", v.toFixed(1), "mini") }
          }
        }
        Row {
          width: parent.width
          spacing: Style.space(10)
          Text {
            text: "Gap"
            color: root.bar ? root.bar.foreground : Color.foreground
            font.family: Style.font.family; font.pixelSize: Style.font.body
            anchors.verticalCenter: parent.verticalCenter
          }
          PanelSlider {
            width: parent.width - Style.space(110)
            minimum: 0; maximum: 10; step: 1
            value: parseFloat(root.readCfg("gap", "mini") || "3")
            onMoved: function(v) { commit("gap", v.toFixed(0), "mini") }
          }
        }
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

        // v7.6: Desktop window spectrum density. Drives the engine's --bands for
        // the detached window and the GL bar count (GL track generalizes NB).
        // Higher = denser/immense spectrum; engine supports up to ~256.
        Row {
          width: parent.width
          spacing: Style.space(10)
          Text {
            text: "Density"
            color: root.bar ? root.bar.foreground : Color.foreground
            font.family: Style.font.family; font.pixelSize: Style.font.body
            anchors.verticalCenter: parent.verticalCenter
          }
          PanelSlider {
            width: parent.width - Style.space(110)
            minimum: 32; maximum: 128; step: 8
            value: parseInt(root.readCfg("density", "desktop") || "128")
            onMoved: function(v) { commit("density", String(Math.round(v)), "desktop") }
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
            id: resetBtn
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
