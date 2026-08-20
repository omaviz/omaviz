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

// T-018 WITHDRAWN (architect-proven): the theory that a bare `Window {` fails
// to map under Hyprland/Quickshell was FALSE — architect empirically confirmed
// a bare Window DOES map. T-018 root cause is now UNCONFIRMED/BLOCKED pending
// live repro, so NO window-type change is applied. Root stays `Window {`.
Window {
  id: win
  width: 600
  height: 200
  visible: true
  color: "#0c0c12"
  flags: Qt.Window | Qt.WindowStaysOnTopHint

  property var spectrumBands: Model.spectrumData.bands
  property bool spectrumSilent: Model.spectrumData.silent
  // T-015: last engine diagnostic line (stderr/exit), surfaced in the window so
  // a capture failure is visible instead of a silent blank canvas.
  property string engineLog: ""
  // Active visual: equalizer -> Bars, oscilloscope -> Oscilloscope,
  // wave -> Wave (GL mode 2). Fire is a color mode, not a visual.
  readonly property string visualName: (win.config.visualDesktop || "equalizer") === "oscilloscope" ? "Oscilloscope"
                                       : (win.config.visualDesktop || "equalizer") === "wave" ? "Wave"
                                       : "Bars"

  Process {
    id: bridge
    running: false
    // v7.6: honor desktop window density (dense spectrum). The engine accepts
    // any N; the GL renderer (VisualCanvasGL.qml) must generalize to N bars.
    command: [Model.engineBin, "--bands", String((win.config && win.config.density) || 128)]
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(data) {
        try {
          var obj = JSON.parse(String(data).trim())
          if (obj && Array.isArray(obj.bands)) {
            win.spectrumBands = obj.bands
            win.spectrumSilent = obj.silent === true
            // T-015: push live bands/silent to the GL item on EVERY frame, not
            // only via the one-shot Binding. Guarantees the renderer always has
            // the latest frame even if the Loader reloaded the item (gpu toggle).
            if (desktopViz.item) {
              desktopViz.item.bands = win.spectrumBands
              desktopViz.item.silent = win.spectrumSilent
            }
          }
        } catch (e) {}
      }
    }
    // T-015: surface engine diagnostics instead of discarding stderr. A capture
    // failure (e.g. node-name collision, no monitor) only printed to stderr; the
    // desktop window dropped it, making silence invisible. Forward to a visible
    // line so the user sees "no audio source" rather than a blank canvas.
    stderr: SplitParser {
      splitMarker: "\n"
      onRead: function(data) {
        var msg = String(data).trim()
        if (msg) win.engineLog = msg
      }
    }
    // Resilience: if the engine exits, try once to respawn it so the window
    // does not get stuck on a static frame (mirrors the bar widget's retry).
    onExited: function(code, status) {
      win.engineLog = "engine exited (code " + code + ")"
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
    // T-015: visible engine-diagnostics line so a capture failure (blank canvas)
    // is diagnosable instead of silent.
    Text {
      width: parent.width; height: 16
      anchors.left: parent.left; anchors.leftMargin: 10
      text: win.engineLog
      color: "#9aa0b5"; font.pixelSize: 10; font.family: "monospace"
      elide: Text.ElideRight
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
        function onConfigChanged() { win.pushSettings() }
      }
      // Also push once when the Loader item first becomes available.
      Connections {
        target: desktopViz
        function onItemChanged() { win.pushSettings() }
      }
    }
  }

  // Push all visualization settings into the renderer item.
  function pushSettings() {
    var it = desktopViz.item
    if (!it) return
    var T = configWrite.text()
    it.visual = win.visualName
    it.colorSource = Model.readTomlValue(T, "desktop", "color_source") || "theme"
    it.customColor = Model.readTomlValue(T, "desktop", "custom_color") || "#5ec8ff"
    it.themeBottom = Model.readTomlValue(T, "desktop", "theme_bottom") || "#e68e0d"
    it.themeTop = Model.readTomlValue(T, "desktop", "theme_top") || "#f59e0b"
    it.fire = Model.readTomlValue(T, "desktop", "fire") === "true"
    it.peaks = Model.readTomlValue(T, "visual.equalizer", "peaks") !== "false"
    it.falloff = Model.readTomlFloat(T, "visual.equalizer", "falloff") ?? 0.5
    it.border = Model.readTomlValue(T, "desktop", "border") !== "false"
    // v7.6: immersive dense desktop spectrum (128 bars, contiguous — barGap 0).
    it.density = (Model.readTomlInt(T, "desktop", "density") || 128)
    it.barGap = 0.0
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
  // config file so bar option changes apply live (100ms for near-instant sync).
  Timer {
    interval: 100; repeat: true; running: true
    onTriggered: configWrite.reload()
  }

  onClosing: {
    // Resume the mini player (#7): clear desktop.active.
    cfgWrite.setText(Model.writeConfigKey(cfgWrite.text(), "desktop", "active", "false"))
  }

  FileView { id: cfgWrite; path: Model.configPath; onFileChanged: {} }
}
