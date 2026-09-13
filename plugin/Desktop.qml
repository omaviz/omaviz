import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

Window {
  id: win
  width: 600
  height: 200
  visible: true
  // Theme-aware window background (dark theme ≈ previous #0c0c12 look).
  color: Color.background
  flags: Qt.Window | Qt.WindowStaysOnTopHint

  property var spectrumBands: Model.spectrumData.bands
  property bool spectrumSilent: Model.spectrumData.silent
  readonly property string visualName: "Bars"
  // Live viz options (peaks/falloff/spikes/fire) — re-parsed on each poll
  // so settings-panel changes reflect in the open window within ~100ms.
  property var vizConfig: Model.defaultConfig()
  function refreshVizConfig() { win.vizConfig = Model.readConfigFromText(cfgWrite.text()) }

  Process {
    id: bridge
    running: false
    // Full-res feed for the big surface: near 1:1 with dense spike bars.
    command: [Model.engineBin, "--bands", "256"]
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
        // Release the shared flag BEFORE closing — FileView writes are
        // async, so give the write time to flush before the window dies.
        onClicked: { win.setDesktopActive(false); closeTimer.restart() }
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
        gapPx: Math.min(6, Math.max(0, win.vizConfig.gap ?? 1))
        minBarHeight: 0

        // Peak settings — live from config (settings panel writes).
        peaks: win.vizConfig.peaks !== false
        peakFalloff: win.vizConfig.peakFalloff ?? 0.5
        spikes: win.vizConfig.spikes === true
        fire: win.vizConfig.fire === true
        splits: win.vizConfig.splits === true
        sensitivity: win.vizConfig.sensitivity ?? 1.0
        themeBottom: win.vizConfig.themeBottom || "#e68e0d"
        themeTop: win.vizConfig.themeTop || "#f59e0b"
      }
    }
  }

  FileView { id: cfgWrite; path: Model.configPath; onFileChanged: {} }
  // Heartbeat lease: refresh every 2s while open so the bar knows this
  // window is LIVE. If the process dies without clearing active (crash,
  // kill -9), the stale flag expires within ~6s and the mini returns.
  Timer {
    interval: 2000; repeat: true; running: true
    onTriggered: win.setDesktopActive(true)
  }
  function setDesktopActive(v) {
    var txt = cfgWrite.text()
    txt = Model.writeConfigKey(txt, "desktop", "active", v ? "true" : "false")
    if (v) txt = Model.writeConfigKey(txt, "desktop", "heartbeat", String(Date.now()))
    cfgWrite.setText(txt)
  }
  // Claim the shared flag once config text is available (covers
  // app-launcher + keybind paths that bypass BarWidget's detach()).
  property bool _claimed: false
  property bool _allowClose: false
  Timer { id: closeTimer; interval: 200; repeat: false; onTriggered: win.close() }
  Timer {
    // Delayed quit: FileView.setText is async — quitting instantly in
    // onClosing can lose the active=false write and leave a stale flag
    // that hides the mini forever. The 300ms wait lets it flush.
    id: quitTimer; interval: 300; repeat: false
    onTriggered: { win._allowClose = true; win.close(); Qt.callLater(Qt.quit) }
  }
  Timer {
    interval: 100; repeat: true; running: true
    onTriggered: {
      cfgWrite.reload()
      win.refreshVizConfig()
      if (!win._claimed && cfgWrite.text().length > 0) {
        win._claimed = true
        win.setDesktopActive(true)
      }
    }
  }

  onClosing: function(close) {
    // Release the shared flag so the mini returns, then actually quit —
    // without Qt.quit() the wrapper process lingers windowless and the
    // mini stays hidden forever (Hyprland killactive only closes the window).
    win.setDesktopActive(false)
    if (!win._allowClose) {
      close.accepted = false
      quitTimer.restart()
    }
  }
}
