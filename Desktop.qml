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
  // so settings-panel changes reflect in the open window within ~250ms.
  property var vizConfig: Model.defaultConfig()
  function refreshVizConfig() { win.vizConfig = Model.readConfigFromText(cfgWrite.text()) }
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
  readonly property string modeName: win.vizConfig.scope === true ? "Omaviz (Scope)" : "Omaviz"
  // Artwork available: MPRIS art URL present and backdrop toggle on.
  readonly property bool hasArt: win.trackArt !== "" && win.vizConfig.artwork !== false
  readonly property string playerSource: win.activePlayer ? (win.activePlayer.identity || win.activePlayer.desktopEntry || "") : ""

  Process {
    id: bridge
    running: false
    // Wave snippet is scope-only: Bars mode never reads it, so omit the
    // flag (and its ~0.7KB/line of JSON.parse) unless scope is on.
    // Fall-mode and scope are spawn-time: restart the bridge on flip.
    command: [Model.engineBin, "--bands", "256"].concat(
      win.vizConfig.scope === true ? ["--wave"] : []).concat(
      win.vizConfig.linearFall === true ? ["--fall-mode", "linear"] : [])
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(data) {
        // 30Hz decimation (perf): paints already throttle to ~30fps, so
        // odd frames are pure parse/physics waste. Peak caps compensate
        // via dataFps (two physics substeps per arrival).
        win._frameSeq++
        if ((win._frameSeq & 1) === 0) return
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

  // Window hover tracking: shows the tray on enter, fades it after
  // a short delay on exit (moving within the window keeps it alive).
  MouseArea {
    id: hoverArea
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.NoButton
    onEntered: { fadeTimer.stop(); trayBox.shown = true }
    onExited: fadeTimer.restart()
  }
  Timer {
    id: fadeTimer
    interval: 350
    repeat: false
    onTriggered: trayBox.shown = false
  }

  Column {
    anchors.fill: parent
    spacing: 0

    Rectangle {
      width: parent.width; height: parent.height; color: "#0c0c12"

      // Artwork backdrop (backdrop toggle): downscaled source = free blur,
      // dimmed so the bars stay readable. Falls back to the
      // canvas wash when no art (radio, browser streams).
      // Plexamp-style backdrop: heavy gaussian blur (no detail survives,
      // only color clouds) + vertical scrim for title/bar legibility.
      // FastBlur caches: static art costs one frame, not per-frame.
      Item {
        anchors.fill: parent
        visible: win.vizConfig.artwork !== false
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
          // Static art: cache the blur, don't re-run a radius-100 kernel
          // every frame (identical pixels — source only changes on track).
          cached: true
        }
        Rectangle {
          anchors.fill: parent
          gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.55) }
            GradientStop { position: 0.45; color: Qt.rgba(0, 0, 0, 0.25) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.60) }
          }
        }
        // Additional darkening overlay on top of blur — adjustable without
        // affecting the blur quality itself. Keeps color clouds visible
        // while making background darker for bar readability.
        Rectangle {
          anchors.fill: parent
          color: Qt.rgba(0, 0, 0, 0.70)
        }
      }

      DotsCanvas {
        anchors.left: parent.left; anchors.right: parent.right
        anchors.leftMargin: 4; anchors.rightMargin: 4
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 4
        height: parent.height - 4
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
        // GPU path parked (Canvas-only for now): ShaderEffect matched
        // feature-for-feature but doubled every renderer change; revisit
        // under GPU_PLAN.md when the viz catalog grows.
        sourceComponent: canvasComp
      }
      Component {
        id: canvasComp
        VisualCanvas {
        // Artwork: centered band (min 60px) so short windows keep it
        // visible instead of sliding it out; otherwise full-bleed.

        bands: win.spectrumBands
        silent: win.spectrumSilent
        wave: win.spectrumWave
        // 30Hz decimated feed (bridge skips odd frames) — peak physics
        // compensates with two substeps per arrival (see dataFps).
        dataFps: 30

        visual: win.vizConfig.scope === true ? "Oscilloscope" : "Bars"
        artMode: false
        wash: win.vizConfig.artwork !== false
        dots: false   // static underlay above
        reflect: win.vizConfig.reflect === true
        scopeLineWidth: win.vizConfig.scopeThickness ?? 2

        colorSync: false
        barCount: Math.max(16, Math.floor((parent.width - 8) / 10))
        gapPx: Math.min(6, Math.max(0, win.vizConfig.gap ?? 1))
        barWidthExtra: 4

        // Peak settings — live from config (settings panel writes).
        peaks: win.vizConfig.peaks !== false
        peakFalloff: win.vizConfig.peakFalloff ?? 0.5
        spikes: win.vizConfig.spikes === true
        fire: win.vizConfig.fire === true
        stacks: win.vizConfig.stacks === true
        stackScale: 2
        sensitivity: win.vizConfig.sensitivity ?? 1.0
        barColorCustom: win.vizConfig.barColorCustom === true
        barColorFrom: win.vizConfig.barColorFrom || "#e68e0d"
        barColorTo: win.vizConfig.barColorTo || "#f59e0b"
        themeBottom: win.vizConfig.themeBottom || "#e68e0d"
        themeTop: win.vizConfig.themeTop || "#f59e0b"
        }
      }

    }
  }

  // ---- Hover tray (Option A): no title bar. Fades in on window hover,
  // out ~200ms after the cursor leaves. Left: artwork thumbnail +
  // monospace track title/artist/source. Right: circular close button,
  // which stays clickable through the fade.
  Item {
    id: trayBox
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: 68
    property bool shown: false
    opacity: shown ? 1.0 : 0.0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

    Rectangle {
      anchors.fill: parent
      gradient: Gradient {
        GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.55) }
        GradientStop { position: 0.6; color: Qt.rgba(0, 0, 0, 0.10) }
        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.0) }
      }
    }

    Row {
      anchors.fill: parent
      anchors.leftMargin: 12
      anchors.rightMargin: 12
      anchors.topMargin: 10
      anchors.bottomMargin: 10
      spacing: 12

      // Artwork thumbnail (48px) or same-size fallback placeholder.
      Item {
        width: 48
        height: 48
        anchors.verticalCenter: parent.verticalCenter

        Rectangle {
          anchors.fill: parent
          radius: 8
          color: "transparent"
          border.width: 1
          border.color: Qt.rgba(255,255,255,0.15)
          visible: !win.hasArt
          Text {
            anchors.centerIn: parent
            text: "♪"
            color: Qt.rgba(255,255,255,0.4)
            font.pixelSize: 18
          }
        }
        Image {
          anchors.fill: parent
          source: win.trackArt
          fillMode: Image.PreserveAspectCrop
          cache: true
          asynchronous: true
          visible: win.hasArt
        }
      }

      // Track info: larger monospace title + artist + theme source line.
      Column {
        width: parent.width - 48 - 12 - 24 - 24
        spacing: 4
        anchors.verticalCenter: parent.verticalCenter

        Text {
          text: win.trackTitle !== "" ? win.trackTitle : win.modeName
          color: "#e8e8f0"
          font.family: "monospace"
          font.pixelSize: 14
          font.bold: true
          elide: Text.ElideRight
          width: parent.width
        }
        Text {
          text: win.trackArtist
          color: Qt.rgba(255,255,255,0.75)
          font.family: "monospace"
          font.pixelSize: 12
          elide: Text.ElideRight
          width: parent.width
          visible: win.trackArtist !== ""
        }
        Text {
          text: win.playerSource
          color: win.vizConfig.themeAccent || "#f59e0b"
          font.family: "monospace"
          font.pixelSize: 10
          elide: Text.ElideRight
          width: parent.width
          visible: win.playerSource !== ""
        }
      }

      // Circular close button: fully steady 16px glyph — no hover
      // reaction at all, so nothing can flash.
      Rectangle {
        id: closeBtn
        width: 24
        height: 24
        radius: 12
        anchors.verticalCenter: parent.verticalCenter
        color: "transparent"

        Text {
          anchors.centerIn: parent
          text: "×"
          color: Qt.rgba(255,255,255,0.75)
          font.pixelSize: 16
          font.family: "monospace"
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          hoverEnabled: true // hand cursor only — no visual hover reaction
          // Release the shared flag BEFORE closing — FileView writes are
          // async, so give the write time to flush before the window dies.
          onClicked: { win.setDesktopActive(false); closeTimer.restart() }
        }
      }
    }
  }

  // Last-external-write guard: the bar also writes this file (option
  // toggles). If the desktop heartbeat fired on a stale base text it
  // would clobber a just-written option and the toggle would snap back
  // (the "needs multiple tries" bug). Skip one beat when another writer
  // was active in the last 1.5s — the 6s lease tolerates the delay.
  property double _lastExternalChange: 0
  FileView { id: cfgWrite; path: Model.configPath; onFileChanged: { win._lastExternalChange = Date.now() } }
  // Heartbeat lease: refresh every 2s while open so the bar knows this
  // window is LIVE. If the process dies without clearing active (crash,
  // kill -9), the stale flag expires within ~6s and the mini returns.
  Timer {
    interval: 2000; repeat: true; running: true
    onTriggered: {
      if (Date.now() - win._lastExternalChange < 1500) return
      win._lastExternalChange = Date.now()
      win.setDesktopActive(true)
    }
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
  property bool _lastScope: false
  // Config-poll guard (perf): the TOML parse + full binding cascade runs
  // only when the file text actually changed — not 4x/sec unconditionally.
  property string _lastCfgText: ""
  // Feed decimation parity (perf): see bridge onRead.
  property int _frameSeq: 0
  Timer { id: closeTimer; interval: 200; repeat: false; onTriggered: win.close() }
  Timer {
    // Delayed quit: FileView.setText is async — quitting instantly in
    // onClosing can lose the active=false write and leave a stale flag
    // that hides the mini forever. The 300ms wait lets it flush.
    id: quitTimer; interval: 300; repeat: false
    onTriggered: { win._allowClose = true; win.close(); Qt.callLater(Qt.quit) }
  }
  Timer {
    // Config poll: 250ms keeps settings-panel changes feeling instant
    // while quartering the JS TOML-parse + binding cascade vs 100ms.
    interval: 250; repeat: true; running: true
    onTriggered: {
      cfgWrite.reload()
      var txt = cfgWrite.text()
      if (txt !== win._lastCfgText) {
        win._lastCfgText = txt
        win.refreshVizConfig()
      }
      // Check enabled state: close window when visualization is disabled
      var enabled = true
      try {
        var val = Model.readTomlValue(txt, "desktop", "enabled")
        enabled = val !== "false"
      } catch(e) {}
      if (!enabled) {
        // Visualization disabled — close the desktop window
        win.setDesktopActive(false)
        closeTimer.restart()
        return
      }
      // Engine flags are spawn-time: restart the bridge when fall-mode or
      // scope flips (scope toggles the --wave feed).
      var lf = win.vizConfig.linearFall === true
      var sc = win.vizConfig.scope === true
      if (win._lastLinearFall !== lf || win._lastScope !== sc) {
        win._lastLinearFall = lf
        win._lastScope = sc
        if (bridge.running) { bridge.running = false; bridge.running = true }
      }
      if (!win._claimed && txt.length > 0) {
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
