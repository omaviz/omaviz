import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Omaviz detached desktop window (v2).
// Launched via `quickshell -p <this file>` from Panel.detach().
// Self-contained: avoids shell-only modules (qs.Commons / qs.Ui) so it
// loads as a standalone Quickshell config. 600x200, renders the live
// visualization (Bars / Wave / Fire) via the shared VisualCanvas.

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
    command: [Model.bridgePath]
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
        source: "VisualCanvas.qml"
      }
      Binding { when: desktopViz.item; target: desktopViz.item; property: "bands"; value: win.spectrumBands }
      Binding { when: desktopViz.item; target: desktopViz.item; property: "silent"; value: win.spectrumSilent }
      Binding { when: desktopViz.item; target: desktopViz.item; property: "visual"; value: win.visualName }
      Binding { when: desktopViz.item; target: desktopViz.item; property: "style"; value: win.visualStyle }
      Binding { when: desktopViz.item; target: desktopViz.item; property: "colorSync"; value: true }
      Binding { when: desktopViz.item; target: desktopViz.item; property: "barCount"; value: Model.readTomlInt(configWrite.text(), "visual.equalizer", "bar_count") || 0 }
      Binding { when: desktopViz.item; target: desktopViz.item; property: "colourScheme"; value: Model.readTomlInt(configWrite.text(), "visual.equalizer", "colour_scheme") || 0 }
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

  onClosing: {
    // Resume the mini player (#7): clear desktop.active.
    cfgWrite.setText(Model.writeConfigKey(cfgWrite.text(), "desktop", "active", "false"))
  }

  FileView { id: cfgWrite; path: Model.configPath; onFileChanged: {} }
}
