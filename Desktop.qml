import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Omaviz detached desktop window (v2, spec §9).
// Launched via `quickshell -p <this file>` from Panel.detach().
// Self-contained: avoids shell-only modules (qs.Commons / qs.Ui) so it
// loads as a standalone Quickshell config. Fixed 400x200 window.

Window {
  id: win
  width: 400
  height: 200
  visible: true
  color: "#0c0c12"
  flags: Qt.Window | Qt.WindowStaysOnTopHint

    // Live spectrum bridge (reuses Model's bridge path).
    property var spectrumBands: Model.spectrumData.bands
    property bool spectrumSilent: Model.spectrumData.silent

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

    Component.onCompleted: {
      // bridgePath has a default in Model.js; start the spectrum bridge now.
      bridge.running = true
    }

    Column {
      anchors.fill: parent
      spacing: 0

      // Title bar
      Rectangle {
        width: parent.width
        height: 26
        color: "#16161f"
        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: 10
          text: "Omaviz — " + (win.config.visualFull || "equalizer")
          color: "#e8e8f0"
          font.pixelSize: 12
          font.family: "monospace"
        }
        Button {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.rightMargin: 6
          width: 22; height: 18
          text: "×"
          onClicked: win.close()
        }
      }

      // Visualization area
      Rectangle {
        id: visArea
        width: parent.width
        height: parent.height - 26
        color: "#0c0c12"

        Repeater {
          id: barRep
          model: win.spectrumBands

          Rectangle {
            x: (visArea.width / Math.max(1, barRep.count)) * index
            width: (visArea.width / Math.max(1, barRep.count)) - 2
            height: visArea.height * Math.min(1, Math.max(0, win.spectrumBands[index] || 0))
            y: visArea.height - height
            radius: 2
            color: {
              var b = win.spectrumBands[index] || 0
              if (b < 0.33) return "#2a9df4"
              if (b < 0.66) return "#9b5de5"
              return "#f15bb5"
            }
          }
        }
      }
    }

    // config (desktop.visual etc.) — read/write via FileView
    property string configPath: Model.configPath
    property var config: Model.readConfigFromText("")
    FileView {
      id: configWrite
      path: Model.configPath
      onFileChanged: {
        win.config = Model.readConfigFromText(configWrite.text())
      }
      Component.onCompleted: {
        win.config = Model.readConfigFromText(configWrite.text())
      }
    }

    onClosing: {
      // Clear desktop.active so the bar widget resumes live viz.
      cfgWrite.setText(Model.writeConfigKey(cfgWrite.text(), "desktop", "active", "false"))
    }

    FileView {
      id: cfgWrite
      path: Model.configPath
      onFileChanged: {}
    }
  }

