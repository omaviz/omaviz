import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Window {
  id: win
  width: 600
  height: 200
  visible: true
  color: "#0c0c12"
  flags: Qt.Window | Qt.WindowStaysOnTopHint

  property var spectrumBands: Model.spectrumData.bands
  property bool spectrumSilent: Model.spectrumData.silent
  readonly property string visualName: "Bars"

  Process {
    id: bridge
    running: false
    command: [Model.engineBin, "--bands", "64"]
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
    onExited: function(code, status) {
      if (win.visible) Qt.callLater(function() { bridge.running = true })
    }
  }

  Component.onCompleted: { bridge.running = true }

  Column {
    anchors.fill: parent
    spacing: 0

    Rectangle {
      width: parent.width; height: 22; color: "#16161f"
      Text {
        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; anchors.leftMargin: 10
        text: "Omaviz — Bars"
        color: "#e8e8f0"; font.pixelSize: 11; font.family: "monospace"
      }
      Button {
        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; anchors.rightMargin: 6
        width: 20; height: 16; text: "×"
        onClicked: win.close()
      }
    }

    Rectangle {
      width: parent.width; height: parent.height - 22; color: "#0c0c12"

      VisualCanvas {
        id: desktopViz
        anchors.fill: parent
        anchors.margins: 4

        bands: win.spectrumBands
        silent: win.spectrumSilent

        visual: "Bars"
        style: "Classic"
        colorSync: false
        barCount: Math.max(16, Math.floor((parent.width - 8) / 10))
        colourScheme: 0
        gapPx: 1
        minBarHeight: 0

        // Peak settings
        peaks: true
        peakFalloff: 0.5
      }
    }
  }

  FileView { id: cfgWrite; path: Model.configPath; onFileChanged: {} }
  Timer {
    interval: 100; repeat: true; running: true
    onTriggered: cfgWrite.reload()
  }

  onClosing: {
    cfgWrite.setText(Model.writeConfigKey(cfgWrite.text(), "desktop", "active", "false"))
  }
}
