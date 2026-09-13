import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Qt5Compat.GraphicalEffects
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
  // GPU renderer: wanted by config (default on), tripped off if the GL
  // pipeline errors — the Canvas fallback then takes over (no-GPU path).
  property bool gpuFailed: false
  readonly property bool gpuActive: win.vizConfig.gpu !== false && !win.gpuFailed
  // ---- Now-playing (MPRIS, zero deps — Quickshell built-in) ----
  // Player pick mirrors the shell media service: prefer a playing source
  // with track metadata, else the first source that has any.
  readonly property var mprisPlayers: Mpris.players ? Mpris.players.values : []
  function pickPlayer() {
    var fallback = null
    for (var i = 0; i < win.mprisPlayers.length; i++) {
      var p = win.mprisPlayers[i]
      if (!p) continue
      var hasTrack = !!(p.trackTitle || p.trackArtist)
      if (p.isPlaying && hasTrack) return p
      if (!fallback && (hasTrack || p.identity || p.desktopEntry)) fallback = p
    }
    return fallback
  }
  readonly property var activePlayer: win.pickPlayer()
  readonly property string trackTitle: win.activePlayer ? (win.activePlayer.trackTitle || "") : ""
  readonly property string trackArtist: win.activePlayer ? (win.activePlayer.trackArtist || "") : ""
  readonly property string trackArt: win.activePlayer ? (win.activePlayer.trackArtUrl || "") : ""
  readonly property string trackLabel: win.trackArtist !== "" ? win.trackArtist + " — " + win.trackTitle : win.trackTitle
  readonly property string modeName: win.vizConfig.artMode === true ? "Omaviz (Artwork)" : (win.vizConfig.scope === true ? "Omaviz (Scope)" : "Omaviz")

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
        anchors.left: parent.left; anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 10; anchors.rightMargin: 30
        text: win.modeName + (win.trackLabel !== "" ? " · " + win.trackLabel : "")
        color: "#e8e8f0"; font.pixelSize: 11; font.family: "monospace"
        elide: Text.ElideRight
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

      // Artwork backdrop (artMode only): downscaled source = free blur,
      // dimmed so the white bars stay readable. Falls back to the
      // canvas wash when no art (radio, browser streams).
      // Plexamp-style backdrop: heavy gaussian blur (no detail survives,
      // only color clouds) + vertical scrim for title/bar legibility.
      // FastBlur caches: static art costs one frame, not per-frame.
      Item {
        anchors.fill: parent
        visible: win.vizConfig.artMode === true && win.vizConfig.artwork !== false
        opacity: win.trackArt !== "" ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 900 } }
        Image {
          id: artSource
          anchors.fill: parent
          source: win.trackArt
          sourceSize.width: 160; sourceSize.height: 160
          fillMode: Image.PreserveAspectCrop
          visible: false
        }
        FastBlur {
          anchors.fill: parent
          source: artSource
          radius: 100
        }
        Rectangle {
          anchors.fill: parent
          gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.62) }
            GradientStop { position: 0.45; color: Qt.rgba(0, 0, 0, 0.30) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.66) }
          }
        }
      }

      DotsCanvas {
        anchors.left: parent.left; anchors.right: parent.right
        anchors.leftMargin: 4; anchors.rightMargin: 4
        anchors.top: win.vizConfig.artMode === true ? undefined : parent.top
        anchors.bottom: win.vizConfig.artMode === true ? undefined : parent.bottom
        anchors.bottomMargin: 4
        height: win.vizConfig.artMode === true ? Math.max(60, parent.height * 0.62) : parent.height - 4
        visible: win.vizConfig.dots !== false
      }
      // Single active renderer (Loader unloads the other): a hidden
      // Canvas still runs its paint JS, so dual instantiation doubles
      // CPU. GPU preferred, Canvas fallback (no-GPU path).
      Loader {
        id: vizLoader
        anchors.left: parent.left; anchors.right: parent.right
        anchors.leftMargin: 4; anchors.rightMargin: 4
        // Bottom-anchored: visualization container hugs bottom of window
        // instead of centering. Minimum 95% of window height, visualization
        // occupies 95% of container height (like preview mode).
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 4
        anchors.top: undefined
        // Height: 95% of parent, with minimum of 100px (was 400, but parent
        // is window height 200px; use proportion instead of fixed min)
        height: Math.max(100, parent.height * 0.95)
        // Visual area occupies 95% of container height
        sourceComponent: win.gpuActive ? gpuComp : canvasComp
      }
      Component {
        id: gpuComp
        GpuCanvas {
        onGpuFailed: win.gpuFailed = true

        bands: win.spectrumBands
        silent: win.spectrumSilent
        wave: win.spectrumWave
        visual: win.vizConfig.scope === true ? "Oscilloscope" : "Bars"
        artMode: win.vizConfig.artMode === true
        dots: false   // static underlay above
        reflect: win.vizConfig.reflect === true
        scopeLineWidth: win.vizConfig.scopeThickness ?? 2
        colorSync: false
        barCount: Math.max(16, Math.floor((parent.width - 8) / 10))
        gapPx: Math.min(6, Math.max(0, win.vizConfig.gap ?? 1))
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
      Component {
        id: canvasComp
        VisualCanvas {
        // Artwork: centered band (min 60px) so short windows keep it
        // visible instead of sliding it out; otherwise full-bleed.

        bands: win.spectrumBands
        silent: win.spectrumSilent
        wave: win.spectrumWave

        visual: win.vizConfig.scope === true ? "Oscilloscope" : "Bars"
        artMode: win.vizConfig.artMode === true
        dots: false   // static underlay above
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
