import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Qt5Compat.GraphicalEffects
import "ModelStore.js" as Store

Window {
  id: win
  width: 600
  height: 200
  minimumWidth: 320
  minimumHeight: 160
  visible: true
  // NOTE: no qs.Commons import here — standalone `quickshell -p` cannot
  // resolve qs.* modules (shell-context only), and the import kills the
  // window on launch. Desktop background stays static dark.
  color: "#0c0c12"
  flags: Qt.Window | Qt.WindowStaysOnTopHint

  readonly property string settingsPath: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/omaviz/config.toml"
  readonly property string leasePath: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/omaviz/desktop-state.toml"
  property var spectrumBands: Store.spectrumData.bands
  property var spectrumWave: []
  property bool spectrumSilent: Store.spectrumData.silent
  // Live viz options (peaks/falloff/spikes/fire) — re-parsed on each poll
  // so settings-panel changes reflect in the open window within ~250ms.
  property var vizConfig: Store.defaultConfig()
  function applySettings(txt) {
    if (!txt || win._closing) return
    if (txt !== win._lastCfgText) {
      win._lastCfgText = txt
      win.vizConfig = Store.loadFromTOML(txt)
    }
    var scope = win.vizConfig.visual !== "Bars"
    if (win.vizConfig.enabled === false) {
      bridgeRetryTimer.stop()
      bridge.running = false
    } else if (scope !== win._lastScope && bridge.running) {
      win._lastScope = scope
      win._restarting = true
      bridge.running = false
    } else {
      win._lastScope = scope
      if (!bridge.running && !win._restarting) bridge.running = true
    }
    if (!win._claimed) { win._claimed = true; win.setDesktopActive(true) }
  }
  ArtworkColors { id: coverPalette; active: win.vizConfig.artworkColors === true && win.vizConfig.visual === "Bars" }
  readonly property bool immersiveArt: win.vizConfig.visual === "Bars" && win.vizConfig.artworkColors === true && coverPalette.colors.length >= 3
  // ---- Now-playing (MPRIS, zero deps — Quickshell built-in) ----
  // Player pick mirrors the shell media service: prefer a playing source
  // with track metadata, else the first source that has any.
  readonly property var mprisPlayers: Mpris.players ? Mpris.players.values : []
  property var preferredPlayer: null
  function pickPlayer() {
    if (win.preferredPlayer && win.mprisPlayers.indexOf(win.preferredPlayer) >= 0) return win.preferredPlayer
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
  readonly property string modeName: "Omaviz — " + (win.vizConfig.visual || "Bars")
  // Artwork available: MPRIS art URL present and backdrop toggle on.
  readonly property bool hasArt: win.trackArt !== "" && win.vizConfig.artwork !== false
  readonly property string playerSource: win.activePlayer ? (win.activePlayer.identity || win.activePlayer.desktopEntry || "") : ""

  Process {
    id: bridge
    running: false
    // Wave snippet is scope-only: Bars mode never reads it, so omit the
    // flag (and its ~0.7KB/line of JSON.parse) unless scope is on.
    // Scope is spawn-time, so the bridge restarts when it flips.
    command: [Store.engineBin, "--bands", "256"].concat(
      win.vizConfig.visual !== "Bars" ? ["--wave"] : [])
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(data) {
        try {
          var obj = JSON.parse(String(data).trim())
          if (obj && Array.isArray(obj.bands)) {
            win.spectrumBands = obj.bands
            win.spectrumSilent = obj.silent === true
            win._bridgeRetries = 0     // a healthy frame resets the backoff
          } else if (obj && Array.isArray(obj.wave)) {
            win.spectrumWave = obj.wave
            win._bridgeRetries = 0
          }
        } catch (e) {}
      }
    }
    // Engine death must never permanently kill the desktop window, and must
    // never become a hot restart loop either: exponential backoff 1.5s -> 30s,
    // identical to the bar widget's. A deliberate restart (scope flip) is
    // flagged so it is not counted as a failure.
    onExited: function(code, status) {
      if (win._restarting) {
        win._restarting = false
        if (!win._closing && win.vizConfig.enabled !== false) bridge.running = true
        return
      }
      if (!win.visible || win._closing || win.vizConfig.enabled === false) return
      win._bridgeRetries++
      bridgeRetryTimer.interval = Math.min(30000, 1500 * win._bridgeRetries)
      bridgeRetryTimer.restart()
    }
  }

  property int _bridgeRetries: 0
  property bool _restarting: false
  Timer { id: bridgeRetryTimer; interval: 1500; repeat: false; onTriggered: if (!win._closing && win.vizConfig.enabled !== false) bridge.running = true }



  // A passive parent handler observes the whole content tree, including buttons.
  // Keyboard access must also reveal the otherwise hover-only controls.
  Shortcut {
    sequence: "Tab"
    enabled: !trayBox.shown
    onActivated: {
      trayBox.shown = true
      Qt.callLater(function() {
        if (playAction.visible && playAction.enabled) playAction.forceActiveFocus()
        else closeAction.forceActiveFocus()
      })
    }
  }
  HoverHandler {
    id: windowHover
    parent: win.contentItem
    blocking: false
    onHoveredChanged: {
      if (hovered) { fadeTimer.stop(); trayBox.shown = true }
      else fadeTimer.restart()
    }
  }
  Timer {
    id: fadeTimer
    interval: 350
    repeat: false
    onTriggered: if (!windowHover.hovered && !playAction.activeFocus && !closeAction.activeFocus) trayBox.shown = false
  }

  Column {
    anchors.fill: parent
    spacing: 0

    Rectangle {
      width: parent.width; height: parent.height; color: win.vizConfig.visual === "Siri" ? "#000000" : "#0c0c12"

      // Artwork backdrop (backdrop toggle): downscaled source = free blur,
      // dimmed so the bars stay readable. Falls back to the
      // canvas wash when no art (radio, browser streams).
      // Plexamp-style backdrop: heavy gaussian blur (no detail survives,
      // only color clouds) + vertical scrim for title/bar legibility.
      // FastBlur caches: static art costs one frame, not per-frame.
      Item {
        anchors.fill: parent
        visible: win.vizConfig.visual === "Bars" && win.vizConfig.artwork !== false
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
          color: Qt.rgba(0, 0, 0, win.immersiveArt ? 0.35 : 0.70)
        }
      }

      // Cover-derived color atmosphere, restrained so spectrum edges stay crisp.
      Rectangle {
        anchors.fill: parent
        visible: win.immersiveArt && win.vizConfig.artwork !== false
        opacity: 0.22
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0; color: coverPalette.colors[0] || "transparent" }
          GradientStop { position: 0.5; color: coverPalette.colors[1] || "transparent" }
          GradientStop { position: 1; color: coverPalette.colors[2] || "transparent" }
        }
      }

      DotsCanvas {
        anchors.left: parent.left; anchors.right: parent.right
        anchors.leftMargin: 4; anchors.rightMargin: 4
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 4
        height: parent.height - 4
        visible: win.vizConfig.dots !== false && win.vizConfig.visual !== "Siri" && win.vizConfig.visual !== "Strings"
      }
      // One active instance of the shared GPU renderer.
      Loader {
        id: vizLoader
        active: win.vizConfig.enabled !== false
        readonly property bool waveform: ["Waves", "Wave", "Oscilloscope", "Strings", "Siri"].includes(win.vizConfig.visual)
        // Fit waveform geometry uniformly: resizing must not turn broad
        // Siri lobes into flat strings or pull standing strings vertically.
        // Spectrum instead fills the surface with width-dependent bar density.
        readonly property real availableWidth: Math.max(0, parent.width - 8)
        readonly property real availableHeight: Math.max(0, parent.height - 8)
        width: waveform ? Math.min(availableWidth, availableHeight * 3) : availableWidth
        height: waveform ? width / 3 : availableHeight
        x: (parent.width - width) / 2
        y: waveform ? (parent.height - height) / 2 : parent.height - height - 4
        // One shared native scene-graph renderer, also used by mini/preview.
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
        // Unified 60Hz feed: identical cadence to the mini/preview, so the
        // fall trajectory is identical on every surface.
        dataFps: 60

        visual: win.vizConfig.visual || "Bars"
        wash: win.vizConfig.artwork !== false
        dots: false   // static underlay above
        reflect: win.vizConfig.reflect === true
        scopeLineWidth: win.vizConfig.scopeThickness ?? 2

        colorSync: win.vizConfig.colorSync !== false
        barCount: Math.max(16, Math.floor((parent.width - 8) / 10))
        gapPx: Math.min(6, Math.max(0, win.vizConfig.gap ?? 1))
        barWidthExtra: 0

        // Peak settings — live from config (settings panel writes).
        peaks: win.vizConfig.peaks !== false
        peakFalloff: win.vizConfig.peakFalloff ?? 0.1
        peakSustainMs: win.vizConfig.peakSustainMs ?? 100
        linearFall: win.vizConfig.linearFall !== false
        noiseFloor: 0.02
        spikes: win.vizConfig.spikes === true
        fire: win.vizConfig.fire === true
        fireColorFrom: win.vizConfig.fireColorFrom || "#be1400"
        fireColorTo: win.vizConfig.fireColorTo || "#fde047"
        stacks: win.vizConfig.stacks === true
        stackScale: 2
        sensitivity: win.vizConfig.sensitivity ?? 1.0
        artworkColors: win.vizConfig.artworkColors === true
        artworkPalette: coverPalette.colors
        barColorCustom: win.vizConfig.barColorCustom === true
        barColorFrom: win.vizConfig.barColorFrom || "#e68e0d"
        barColorTo: win.vizConfig.barColorTo || "#f59e0b"
        barColorMiddle: win.vizConfig.barColorMiddle || "#a855f7"
        barColorMiddleEnabled: win.vizConfig.barColorMiddleEnabled === true
        gradientDir: win.vizConfig.barGradientDir || "vertical"
        themeBottom: win.vizConfig.themeBottom || "#e68e0d"
        themeTop: win.vizConfig.themeTop || "#f59e0b"
        }
      }

    }
  }

  Text {
    anchors.centerIn: parent
    visible: win.vizConfig.enabled === false
    text: "Visualization paused"
    color: "#b0b6c2"
    font.pixelSize: 14
  }

  function togglePlayback() {
    var player = win.activePlayer
    if (!player || !player.canControl) return
    // Keep the controlled source selected after it pauses.
    win.preferredPlayer = player
    if (player.isPlaying && player.canPause) player.pause()
    else if (!player.isPlaying && player.canPlay) player.play()
    else if (player.canTogglePlaying) player.togglePlaying()
  }

  // Compact now-playing card; playback follows the selected player's capabilities.
  Rectangle {
    id: trayBox
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.margins: 12
    height: 88
    radius: 14
    color: "#ed151820"
    border.color: "#32ffffff"
    border.width: 1
    property bool shown: false
    readonly property bool canToggle: !!win.activePlayer && win.activePlayer.canControl && (win.activePlayer.canTogglePlaying || (win.activePlayer.isPlaying ? win.activePlayer.canPause : win.activePlayer.canPlay))
    opacity: shown ? 1.0 : 0.0
    visible: shown || opacity > 0.01
    enabled: shown
    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    Row {
      anchors.fill: parent
      anchors.margins: 12
      spacing: 12
      Rectangle {
        width: 64; height: 64
        radius: 8
        color: "#272d39"
        clip: true
        Text {
          anchors.centerIn: parent
          text: "♪"
          color: "#aeb6c6"
          font.pixelSize: 26
        }
        Image {
          anchors.fill: parent
          source: win.trackArt
          sourceSize.width: 128
          sourceSize.height: 128
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          visible: status === Image.Ready
        }
      }
      Column {
        width: Math.max(0, parent.width - 64 - actions.width - 24)
        spacing: 4
        anchors.verticalCenter: parent.verticalCenter
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: win.playerSource || "OMAVIZ"
          color: "#aeb6c6"
          font.pixelSize: 10
          font.letterSpacing: 1
          elide: Text.ElideRight
        }
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: win.trackTitle || win.modeName
          color: "#f5f6fa"
          font.pixelSize: 15
          font.bold: true
          elide: Text.ElideRight
        }
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: win.trackArtist || (win.activePlayer ? (win.activePlayer.isPlaying ? "Playing" : "Paused") : "Listening to system audio")
          color: "#aeb6c6"
          font.pixelSize: 12
          elide: Text.ElideRight
        }
      }
      Row {
        id: actions
        spacing: 8
        anchors.verticalCenter: parent.verticalCenter
        TrayAction {
          id: playAction
          visible: !!win.activePlayer && win.activePlayer.canControl
          enabled: trayBox.canToggle
          opacity: enabled ? 1 : 0.4
          label: win.activePlayer && win.activePlayer.isPlaying ? "Ⅱ" : "▶"
          accessibleLabel: win.activePlayer && win.activePlayer.isPlaying ? "Pause" : "Play"
          onTriggered: win.togglePlayback()
        }
        TrayAction {
          id: closeAction
          label: "×"
          accessibleLabel: "Close desktop visualizer"
          onTriggered: { win.setDesktopActive(false); closeTimer.restart() }
        }
      }
    }
  }

  component TrayAction: Rectangle {
    id: action
    property string label: ""
    property string accessibleLabel: ""
    signal triggered()
    width: 36; height: 36; radius: 18
    color: pointer.containsMouse || activeFocus ? "#485268" : "#2c3341"
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: accessibleLabel
    Accessible.onPressAction: triggered()
    Keys.onSpacePressed: triggered()
    Keys.onReturnPressed: triggered()
    Text {
      anchors.centerIn: parent
      text: action.label
      color: "#f5f6fa"
      font.pixelSize: 18
    }
    MouseArea {
      id: pointer
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: action.triggered()
    }
  }

  // Heartbeats have their own file: this window only READS settings.
  FileView {
    id: cfgWrite
    path: win.settingsPath
    watchChanges: true
    onFileChanged: reload()
    onLoaded: win.applySettings(text() || (win._claimed ? "" : Store.toTOML(Store.defaultConfig())))
    onLoadFailed: if (!win._claimed) win.applySettings(Store.toTOML(Store.defaultConfig()))
  }
  FileView {
    id: desktopState
    path: win.leasePath
    printErrors: false
    onLoaded: {
      if (win._claimed && !win._closing && Store.readTomlValue(text(), "desktop", "active") === "false") {
        win.setDesktopActive(false)
        closeTimer.start()
      }
    }
  }
  property bool _closing: false
  Timer {
    interval: 2000; repeat: true; running: win._claimed && !win._closing
    onTriggered: win.setDesktopActive(true)
  }
  function setDesktopActive(v) {
    if (!v) { win._closing = true; bridgeRetryTimer.stop(); bridge.running = false }
    desktopState.setText("[desktop]\nactive = " + v + "\nheartbeat = " + Date.now() + "\n")
  }
  // Claim the shared flag once config text is available (covers
  // app-launcher + keybind paths that bypass BarWidget's detach()).
  property bool _claimed: false
  property bool _allowClose: false
  property bool _lastScope: false
  // Config-poll guard (perf): the TOML parse + full binding cascade runs
  // only when the file text actually changed — not 4x/sec unconditionally.
  property string _lastCfgText: ""
  Timer { id: closeTimer; interval: 200; repeat: false; onTriggered: win.close() }
  Timer {
    // Delayed quit: FileView.setText is async — quitting instantly in
    // onClosing can lose the active=false write and leave a stale flag
    // that hides the mini forever. The 300ms wait lets it flush.
    id: quitTimer; interval: 300; repeat: false
    onTriggered: { win._allowClose = true; win.close(); Qt.callLater(Qt.quit) }
  }
  Timer {
    // Reload asynchronously; onLoaded applies the completed snapshot.
    interval: 100; repeat: true; running: !win._closing
    onTriggered: { cfgWrite.reload(); desktopState.reload() }
  }

  IpcHandler {
    target: "omaviz-desktop"
    function status(): string {
      return JSON.stringify({visual: win.vizConfig.visual, enabled: win.vizConfig.enabled,
        waveSamples: win.spectrumWave.length, configPath: win.settingsPath, engineRunning: bridge.running, closing: win._closing,
        trayVisible: trayBox.shown, playbackVisible: !!win.activePlayer && win.activePlayer.canControl})
    }
    function quit() { win.setDesktopActive(false); closeTimer.restart() }
  }

  onClosing: function(close) {
    // Release the shared flag so the mini returns, then actually quit —
    // without Qt.quit() the wrapper process lingers windowless and the
    // mini stays hidden forever (Hyprland killactive only closes the window).
    if (!win._closing) win.setDesktopActive(false)
    if (!win._allowClose) {
      close.accepted = false
      quitTimer.restart()
    }
  }
}
