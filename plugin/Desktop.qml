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
  // NOTE: no qs.Commons import here — standalone `quickshell -p` cannot
  // resolve qs.* modules (shell-context only), and the import kills the
  // window on launch. Desktop background stays static dark.
  color: "#0c0c12"
  flags: Qt.Window | Qt.WindowStaysOnTopHint

  property var spectrumBands: Model.spectrumData.bands
  property var spectrumWave: []
  property bool spectrumSilent: Model.spectrumData.silent
  // Live viz options (peaks/falloff/spikes/fire) — re-parsed on each poll
  // so settings-panel changes reflect in the open window within ~100ms.
  property var vizConfig: Model.defaultConfig()
  function refreshVizConfig() { win.vizConfig = Model.readConfigFromText(cfgWrite.text()) }
  // Local option writers: same single-write discipline as BarWidget
  // (one base text, one setText). Engine-flag changes are picked up by
  // the 100ms poll loop, which restarts the bridge on fall-mode flips.
  function vizVal(value) {
    if (typeof value === "boolean") return value ? "true" : "false"
    return String(value)
  }
  function writeVizOptions(key1, value1, key2, value2) {
    var txt = cfgWrite.text()
    txt = Model.writeConfigKey(txt, "desktop", key1, win.vizVal(value1))
    if (key2) txt = Model.writeConfigKey(txt, "desktop", key2, win.vizVal(value2))
    cfgWrite.setText(txt)
    win.refreshVizConfig()
  }
  function writeVizOption(key, value) { win.writeVizOptions(key, value, null, null) }
  function writeEngineOption(key, value) { win.writeVizOption(key, value) }
  // Hover-drawer state (Option 2: settings reachable without closing).
  property bool hovering: false
  property bool drawerOpen: false

  Process {
    id: bridge
    running: false
    // Full-res feed for the big surface: near 1:1 with dense spike bars.
    // --wave for scope mode; fall-mode follows config (restarted on change).
    command: [Model.engineBin, "--bands", "256", "--wave"].concat(
      win.vizConfig.linearFall === true ? ["--fall-mode", "linear"] : [])
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(data) {
        try {
          var obj = JSON.parse(String(data).trim())
          if (obj && Array.isArray(obj.bands)) {
            win.spectrumBands = obj.bands
            win.spectrumSilent = obj.silent === true
          } else if (obj && Array.isArray(obj.wave)) {
            win.spectrumWave = obj.wave
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
        text: win.vizConfig.scope === true ? "Omaviz — Scope" : "Omaviz — Bars"
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

      // Hover sensor: reveals the gear without swallowing clicks.
      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onEntered: win.hovering = true
        onExited: win.hovering = false
      }

      VisualCanvas {
        id: desktopViz
        anchors.fill: parent
        anchors.margins: 4

        bands: win.spectrumBands
        silent: win.spectrumSilent
        wave: win.spectrumWave

        visual: win.vizConfig.scope === true ? "Oscilloscope" : "Bars"
        dots: win.vizConfig.dots !== false
        reflect: win.vizConfig.reflect === true
        scopeLineWidth: win.vizConfig.scopeThickness ?? 2

        colorSync: false
        barCount: Math.max(16, Math.floor((parent.width - 8) / 10))
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

      // Gear: fades in on hover, toggles the settings drawer.
      Text {
        text: "⚙"
        anchors.right: parent.right; anchors.top: parent.top
        anchors.rightMargin: 8; anchors.topMargin: 4
        color: "#e8e8f0"; font.pixelSize: 16
        opacity: (win.hovering || win.drawerOpen) ? 0.9 : 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
        MouseArea {
          anchors.fill: parent; anchors.margins: -6
          onClicked: win.drawerOpen = !win.drawerOpen
        }
      }

      // Settings drawer: the shared OptionsForm, applied live to this
      // window — no close/reopen round-trip, no lost window size.
      Rectangle {
        visible: win.drawerOpen
        anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom
        width: 264
        color: "#14141cf2"
        border.width: 1; border.color: "#3a3a48"
        Flickable {
          anchors.fill: parent; anchors.margins: 10
          contentHeight: drawerForm.height
          clip: true
          Column {
            id: drawerForm
            width: parent.width
            spacing: 2
            Text { text: "SETTINGS"; color: "#9a9ab0"; font.pixelSize: 11; font.letterSpacing: 1 }
            OptionsForm {
              width: parent.width
              cfg: win.vizConfig
              onVizOption: function(key, value) { win.writeVizOption(key, value) }
              onVizOptions: function(k1, v1, k2, v2) { win.writeVizOptions(k1, v1, k2, v2) }
              onEngineOption: function(key, value) { win.writeEngineOption(key, value) }
            }
          }
        }
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
  property bool _lastLinearFall: false
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
      // Engine flags are spawn-time: restart the bridge when fall-mode flips.
      var lf = win.vizConfig.linearFall === true
      if (win._lastLinearFall !== lf) {
        win._lastLinearFall = lf
        if (bridge.running) { bridge.running = false; bridge.running = true }
      }
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
