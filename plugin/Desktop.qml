import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Omaviz detached desktop window (v7).
// Launched via `quickshell -p <this file>` from Panel.detach().
// Self-contained: avoids shell-only modules (qs.Commons / qs.Ui) so it
// loads as a standalone Quickshell config. 600x200, renders the live
// visualization (Bars / Wave / Fire) via the shared VisualCanvas.
// Spawns the bundled engine (Model.engineBin) — same source the bar uses.

Window {
  id: win
  width: 600
  height: 200
  visible: true
  color: "#0c0c12"
  flags: Qt.Window | Qt.WindowStaysOnTopHint

  property var spectrumBands: Model.spectrumData.bands
  property bool spectrumSilent: Model.spectrumData.silent
  // Active visual display name (Bars/Wave/Fire).
  readonly property string visualName: (win.config.visualDesktop || "equalizer")
    .replace("equalizer", "Bars").replace("wave", "Wave").replace("fire", "Fire")
  // Fire is a STYLE of the Bars visual, not a separate visualization.
  readonly property string visualStyle: (win.config.styleDesktop || "classic") === "fire" ? "Fire" : "Classic"

  Process {
    id: bridge
    running: false
    command: [Model.engineBin, "--source", "auto", "--bands", "32"]
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(data) {
        try {
          var obj = JSON.parse(String(data).trim())
          if (obj && Array.isArray(obj.bands)) {
            win.spectrumBands = obj.bands
            win.spectrumSilent = obj.silent === true
          }
        } catch (e) {}
      }
    }
    // Resilience: if the engine exits, try once to respawn it so the window
    // does not get stuck on a static frame (mirrors the bar widget's retry).
    onExited: function(code, status) {
      if (win.visible) Qt.callLater(function() { bridge.running = true })
    }
  }

  Component.onCompleted: { bridge.running = true }

  Column {
    anchors.fill: parent
    spacing: 0

    Rectangle {
      width: parent.width; height: 26; color: "#16161f"
      Text {
        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; anchors.leftMargin: 10
        text: "Omaviz — " + win.visualName + (win.visualStyle === "Fire" ? " · Fire" : "")
        color: "#e8e8f0"; font.pixelSize: 12; font.family: "monospace"
      }
      Button {
        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; anchors.rightMargin: 6
        width: 22; height: 18; text: "×"
        onClicked: win.close()
      }
    }

    Rectangle {
      id: visArea
      width: parent.width; height: parent.height - 26; color: "#0c0c12"
      Loader {
        id: desktopViz
        anchors.fill: parent
        source: (win.config.gpu === false) ? "VisualCanvas.qml" : "VisualCanvasGL.qml"
      }
      // Live data that updates every frame (works via Binding).
      Binding { when: desktopViz.item; target: desktopViz.item; property: "bands"; value: win.spectrumBands }
      Binding { when: desktopViz.item; target: desktopViz.item; property: "silent"; value: win.spectrumSilent }
      // Settings (visual/style/scheme/color): push directly on config change,
      // not via the fragile Binding-when chain — those can miss re-evaluations.
      Connections {
        target: win
        function onConfigChanged() { pushSettings() }
      }
      // Also push once when the Loader item first becomes available.
      Connections {
        target: desktopViz
        function onItemChanged() { pushSettings() }
      }
      function pushSettings() {
        var it = desktopViz.item
        if (!it) return
        it.visual = win.visualName
        it.style = win.visualStyle
        it.colorSync = true
        it.colourScheme = Model.readTomlInt(configWrite.text(), "visual.equalizer", "colour_scheme") || 0
        it.barCount = Model.readTomlInt(configWrite.text(), "visual.equalizer", "bar_count") || 0
        it.border = Model.readTomlValue(configWrite.text(), "desktop", "border") !== "false"
        it.render3d = Model.readTomlValue(configWrite.text(), "desktop", "render3d") === "true"
        it.colorSource = Model.readTomlValue(configWrite.text(), "desktop", "color_source") || "theme"
        var cc = Model.readTomlValue(configWrite.text(), "desktop", "custom_color") || "#5ec8ff"
        it.customColor = cc
        it.themeBottom = Model.readTomlValue(configWrite.text(), "desktop", "theme_bottom") || "#19e0d4"
        it.themeTop = Model.readTomlValue(configWrite.text(), "desktop", "theme_top") || "#a45cff"
      }
    }
  }

  property string configPath: Model.configPath
  property var config: Model.readConfigFromText("")
  FileView {
    id: configWrite
    path: Model.configPath
    onLoaded: { win.config = Model.readConfigFromText(text()) }
    onFileChanged: { win.config = Model.readConfigFromText(text()) }
  }
  // The detached window is a SEPARATE quickshell process, so it cannot rely on
  // cross-process FileView watch signals to learn of panel edits. Poll the
  // config file so visual/style/scheme changes apply live.
  Timer {
    interval: 300; repeat: true; running: true
    onTriggered: configWrite.reload()
  }

  onClosing: {
    // Resume the mini player (#7): clear desktop.active.
    cfgWrite.setText(Model.writeConfigKey(cfgWrite.text(), "desktop", "active", "false"))
  }

  FileView { id: cfgWrite; path: Model.configPath; onFileChanged: {} }
}
