import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
// T-014 (ADR-0008, approved path correction): the plugin imports the SHELL
// module names qs.Commons / qs.Ui. Module-name imports work in the shell
// mini-bar context. Do NOT use the relative "qs/Ui" form.
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

  // ---- Forwarded controller-open (T-014) ----
  // The popup surface reads `panelController.open` from the shared qs.Ui Panel
  // base. Bind it locally so the change signal is unambiguously local and the
  // KeyboardPanel never silently binds to an unresolved inherited property.
  readonly property bool _ctrlOpen: (typeof panelController !== "undefined" && panelController)
    ? panelController.open : false

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
    var v = root.readCfg("visual", "mini") || "equalizer"
    if (v === "oscilloscope") return "Wave"
    if (v === "wave") return "Wave"
    return "Bars"
  }
  function currentStyle() {
    return (root.readCfg("style", "mini") || "classic") === "fire" ? "Fire" : "Classic"
  }

  // ---- Source (read-only, from the engine's stdout) ----
  readonly property string sourceLabelText:
    Model.sourceLabel(Model.spectrumData.source || "")

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
    // T-019: removed the previous full-parent anchor assignment — KeyboardPanel
    // is a PanelWindow (Quickshell window type) with NO anchors property; that
    // line raised "Cannot assign to non-existent property fill" and aborted
    // panel construction (ADR-0011). KeyboardPanel fills its layer-shell
    // surface internally, so no replacement is needed.
    // T-014: fallback anchor chain so the popup always has a valid anchor even
    // if injectPanel() has not yet set anchorItem/hostWidget (null on first
    // show -> off-screen/invisible). Fallback to bar, then root, mirrors the
    // existing `bar: root.bar` strategy.
    anchorItem: root.anchorItem || root.bar || root
    owner: root.hostWidget || root.bar || root
    bar: root.bar
    open: root._ctrlOpen
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(720))
    // T-014: the shared KeyboardPanel takes `anchorItem` as a required property and
    // re-derives its geometry from it via bindings, so a late anchor resolves to a
    // visible popup automatically — no manual forceLayout() call is needed (the
    // KeyboardPanel exposes no such method, T-022).

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
            barCount: (root.config.density || 64)   // dense preview reflects the desktop window
            colourScheme: 0
          }
        }
        // The settings preview is the Canvas-2D VisualCanvas (Panel.qml:185), NOT
        // a Loader, so `previewViz.item` is always undefined. Binding to it emits
        // "Unable to assign [undefined]" warnings (live log 5jxiodn2kt, 18x) and
        // does nothing. The GL-only style props (border/colorSource/customColor/
        // themeBottom/themeTop/fire/peaks/falloff/alpha) also don't exist on the
        // 2D canvas. The 2D preview already receives its valid props inline above
        // (186-191); do NOT re-bind GL-only props here (T-022 regression guard).

        PanelSeparator { }

        // ---- VISUALIZATION (Bar / Oscilloscope / Wave; Fire is a style, not a viz) ----
        PanelSectionHeader { text: "VISUALIZATION" }
        ButtonGroup {
          id: vizGroup
          width: parent.width
          options: ["Bar", "Oscilloscope", "Wave"]
          property string cfgViz: (root.readCfg("visual", "mini") || "equalizer")
          value: cfgViz === "oscilloscope" ? "Oscilloscope"
                 : cfgViz === "wave" ? "Wave"
                 : "Bar"
          onChanged: function(v) {
            var key = v === "Oscilloscope" ? "oscilloscope"
                    : v === "Wave" ? "wave"
                    : "equalizer"
            commit("visual", key, "mini")
            commit("visual", key, "desktop")
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
            commit("style", key, "mini")
            commit("style", key, "desktop")
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
              commit("mode", (v === "Lines" ? "lines" : "bars"), "visual.equalizer")
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
              commit("color", key, "visual.equalizer")
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
              commit("color_source", (v === "Custom" ? "custom" : "theme"), "desktop")
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

        // ---- Footer: Reset ----
        Row {
          width: parent.width
          spacing: Style.space(8)
          Button {
            id: resetBtn
            text: "Reset"
            onClicked: root.resetAll()
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
