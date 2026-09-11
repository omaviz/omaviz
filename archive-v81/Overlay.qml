import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Omaviz big-window mode (v8.1) — overlay kind, runs INSIDE the shared shell
// process (clipboard/emojis pattern): fullscreen layer surface with a centered
// visualizer card. Summoned via `omarchy-shell shell summon io.github.kishan.omaviz`.
// Shares the same Model.spectrumData the bar mini feeds — zero extra capture.

Item {
  id: root

  property string moduleName: "io.github.kishan.omaviz"
  property bool opened: false
  property var config: Model.defaultConfig()

  function open(payloadJson) {
    root.opened = true
  }
  function close() {
    root.opened = false
  }

  readonly property int cardWidth: Math.min(Style.space(1100), panel.width - Style.gapsOut * 2)
  readonly property int cardHeight: Math.min(Style.space(620), panel.height - Style.gapsOut * 2)

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omaviz-overlay"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // scrim
    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
      MouseArea {
        anchors.fill: parent
        onClicked: root.close()
      }
    }

    // visualizer card
    Rectangle {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      anchors.centerIn: parent
      color: Color.menu.background
      radius: Style.cornerRadius
      border.width: 1
      border.color: Color.menu.border

      VisualCanvasGL {
        id: viz
        anchors.fill: parent
        anchors.margins: Style.space(16)
        // Model.spectrumData is a plain JS object — assignments don't emit
        // change notifications, so poll it into a local (notified) property.
        property var _liveBands: []
        property bool _liveSilent: true
        Timer {
          interval: 16; repeat: true; running: root.opened
          onTriggered: {
            viz._liveBands = Model.spectrumData.bands
            viz._liveSilent = Model.spectrumData.silent
          }
        }
        bands: viz._liveBands
        silent: viz._liveSilent
        visual: (root.config.visualDesktop === "oscilloscope") ? "Oscilloscope" : "Bars"
        colorSource: root.config.colorSource || "theme"
        themeBottom: root.config.themeBottom || "#e68e0d"
        themeTop: root.config.themeTop || "#f59e0b"
        customColor: root.config.customColor || "#5ec8ff"
        fire: root.config.fire === true
        peaks: root.config.eqPeaks !== false
        falloff: root.config.eqFalloff ?? 0.5
        border: root.config.border !== false
        alpha: 1.0
      }

      // header hint
      Text {
        anchors { top: parent.top; left: parent.left; margins: Style.space(12) }
        text: "omaviz — Esc or click outside to close"
        color: Color.menu.text
        opacity: 0.6
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }

      Keys.onEscapePressed: root.close()
    }

    PanelKeyCatcher {
      anchors.fill: parent
      onCloseRequested: root.close()
    }
  }

  // Notify the bar widget so it unpauses the mini when the overlay closes.
  onOpenedChanged: {
    // The bar's IpcHandler exposes overlayOpen/overlayClosed; the shell IPC
    // round-trip is avoided — both live in the same process, but the bar
    // widget instance is a separate component tree. Use the config flag as
    // the shared source of truth; the bar watches it via FileView.
  }
}
