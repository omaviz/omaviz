import QtQuick
import QtQuick.Controls
import QtCore
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
  readonly property var spectrumBands: bridge.bands
  readonly property var spectrumWave: bridge.wave
  readonly property bool spectrumSilent: bridge.silent
  readonly property var vizConfig: visualTransition.presented
  VisualTransition { id: visualTransition; config: settingsDocument.config }
  SettingsDocument {
    id: settingsDocument
    path: win.settingsPath
    pollInterval: 250
    onReadyChanged: if (ready && !win._claimed && !win._closing) {
      win._claimed = true
      win.setDesktopActive(true)
    }
  }
  ArtworkColors { id: coverPalette; player: media.player; active: win.vizConfig.artworkColors === true && Store.supportsArtwork(win.vizConfig.visual) }
  readonly property bool immersiveArt: win.vizConfig.visual === "Bars" && win.vizConfig.artworkColors === true && coverPalette.colors.length >= 3
  MediaSession { id: media }
  readonly property var activePlayer: media.player
  readonly property string trackTitle: win.activePlayer ? (win.activePlayer.trackTitle || "") : ""
  readonly property string trackArtist: win.activePlayer ? (win.activePlayer.trackArtist || "") : ""
  readonly property string trackArt: win.activePlayer ? (win.activePlayer.trackArtUrl || "") : ""
  readonly property string trackLabel: win.trackArtist !== "" ? win.trackArtist + " — " + win.trackTitle : win.trackTitle
  readonly property string modeName: "Omaviz — " + Store.visualLabel(win.vizConfig.visual || "Bars")
  // Artwork available: MPRIS art URL present and backdrop toggle on.
  readonly property bool hasArt: win.trackArt !== "" && win.vizConfig.artwork !== false
  readonly property string playerSource: win.activePlayer ? (win.activePlayer.identity || win.activePlayer.desktopEntry || "") : ""

  EngineFeed {
    id: bridge
    active: settingsDocument.ready && win.vizConfig.enabled !== false && !win._closing
    waveEnabled: win.vizConfig.visual !== "Bars"
    siriEnabled: win.vizConfig.visual === "Siri"
    stringsEnabled: win.vizConfig.visual === "Strings"
    bandCount: 256
  }

  // A passive parent handler observes the whole content tree, including buttons.
  // Keyboard access must also reveal the otherwise hover-only controls.
  property int transportIdleMs: 30000
  function revealTransport() { trayBox.shown = true; fadeTimer.restart() }
  Shortcut {
    sequence: "Tab"
    enabled: !trayBox.shown
    onActivated: {
      win.revealTransport()
      Qt.callLater(trayBox.focusPlayback)
    }
  }
  HoverHandler {
    id: windowHover
    parent: win.contentItem
    blocking: false
    property point cursorPosition: point.position
    onHoveredChanged: {
      if (hovered) win.revealTransport()
    }
    onCursorPositionChanged: if (hovered) win.revealTransport()
  }
  Timer {
    id: fadeTimer; objectName: "transportIdleTimer"
    interval: win.transportIdleMs
    repeat: false
    onTriggered: trayBox.shown = false
  }

  Column {
    opacity: visualTransition.fade
    anchors.fill: parent
    spacing: 0

    Rectangle {
      width: parent.width; height: parent.height; color: win.vizConfig.visual === "Siri" || win.vizConfig.visual === "Cosmos" ? "#000000" : "#0c0c12"

      // Artwork backdrop (backdrop toggle): downscaled source = free blur,
      // dimmed so the bars stay readable. Falls back to the
      // canvas wash when no art (radio, browser streams).
      // Plexamp-style backdrop: heavy gaussian blur (no detail survives,
      // only color clouds) + vertical scrim for title/bar legibility.
      // FastBlur caches: static art costs one frame, not per-frame.
      Loader {
        id: artBackdrop
        anchors.fill: parent
        // Unload the entire cached blur whenever the selected mode does not
        // support artwork; no frozen image can survive a mode transition.
        active: win.hasArt && Store.supportsArtwork(win.vizConfig.visual)
        sourceComponent: Component {
          Item {
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
              color: Qt.rgba(0, 0, 0, win.immersiveArt || Store.isAmbient(win.vizConfig.visual) ? 0.35 : 0.70)
            }
          }
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

      // Keep the inset frame black even when an artwork backdrop is loaded.
      Rectangle {
        anchors.fill: parent
        visible: win.vizConfig.visual === "Cosmos"
        color: "#000000"
      }
      DotsCanvas {
        anchors.left: parent.left; anchors.right: parent.right
        anchors.leftMargin: 4; anchors.rightMargin: 4
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 4
        height: parent.height - 4
        visible: win.vizConfig.dots !== false && win.vizConfig.visual !== "Siri" && win.vizConfig.visual !== "Strings" && !Store.isAmbient(win.vizConfig.visual)
      }
      // One active instance of the shared GPU renderer.
      Loader {
        id: vizLoader
        active: win.vizConfig.enabled !== false
        readonly property bool waveform: ["Waves", "Wave", "Oscilloscope", "Strings", "Siri"].includes(win.vizConfig.visual)
        // Siri/Waves preserve their 3:1 silhouette. Strings uses the full
        // desktop surface so its standing waves fill tall/wide windows too.
        readonly property real availableWidth: Math.max(0, parent.width - 8)
        readonly property real availableHeight: Math.max(0, parent.height - 8)
        readonly property bool fittedWave: waveform && win.vizConfig.visual !== "Strings"
        readonly property int spectrumBarCount: Math.max(16, Math.floor(availableWidth /
          (10 + 8 * Math.min(1, Math.max(0, (availableWidth - 600) / 600)))))
        width: fittedWave ? Math.min(availableWidth, availableHeight * 3) : availableWidth
        height: fittedWave ? width / 3 : availableHeight
        x: (parent.width - width) / 2
        y: fittedWave ? (parent.height - height) / 2 : parent.height - height - 4
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
        waveRms: bridge.waveRms
        wave: win.spectrumWave
        waveSerial: bridge.waveSerial
        bandLayout: bridge.bandLayout
        // Unified 60Hz feed: identical cadence to the mini/preview, so the
        // fall trajectory is identical on every surface.
        dataFps: 60

        visual: win.vizConfig.visual || "Bars"
        wash: win.vizConfig.artwork !== false
        dots: false   // static underlay above
        reflect: win.vizConfig.reflect === true
        scopeLineWidth: win.vizConfig.scopeThickness ?? 2
        siriClassic: win.vizConfig.siriClassic === true
        siriTravel: win.vizConfig.siriTravel === true

        colorSync: win.vizConfig.colorSync !== false
        barCount: vizLoader.spectrumBarCount
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
        originalColors: win.vizConfig.colorMode === "Original"
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

  TransportPanel {
    id: trayBox
    anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom
    anchors.bottomMargin: 12
    width: Math.min(480, parent.width - 24)
    player: media.player
    fallbackTitle: win.modeName
    status: bridge.status
    creditText: win.vizConfig.visual === "Cosmos" ? 'Milky Way: <a href="https://www.eso.org/public/images/eso0932a/">ESO/S. Brunier</a><br/><a href="https://creativecommons.org/licenses/by/4.0/">CC BY 4.0</a> · adapted panorama' : ""
    creditUrl: "https://www.eso.org/public/images/eso0932a/"
    onToggleRequested: { win.revealTransport(); media.toggle() }
    onPreviousRequested: { win.revealTransport(); media.previous() }
    onNextRequested: { win.revealTransport(); media.next() }
    onCloseRequested: { win.setDesktopActive(false); closeTimer.restart() }
  }

  Settings {
    id: windowState
    location: "file://" + win.settingsPath.replace(/config\.toml$/, "desktop-window.ini")
    property int normalWidth: 600
    property int normalHeight: 200
  }
  Component.onCompleted: {
    width = Math.max(minimumWidth, Math.min(windowState.normalWidth, Screen.width))
    height = Math.max(minimumHeight, Math.min(windowState.normalHeight, Screen.height))
  }
  Timer {
    id: saveSize; interval: 500
    onTriggered: if (win.visibility === Window.Windowed) {
      windowState.normalWidth = win.width
      windowState.normalHeight = win.height
    }
  }
  onWidthChanged: saveSize.restart()
  onHeightChanged: saveSize.restart()
  function toggleFullscreen() {
    win.visibility = win.visibility === Window.FullScreen ? Window.Windowed : Window.FullScreen
  }
  function handleEscape() {
    if (win.visibility === Window.FullScreen) win.visibility = Window.Windowed
    else { win.setDesktopActive(false); closeTimer.restart() }
  }
  Shortcut { sequence: "F11"; onActivated: win.toggleFullscreen() }
  Shortcut { sequence: "Escape"; onActivated: win.handleEscape() }
  Process { id: visualCommand }
  function cycleVisual(direction) {
    if (visualCommand.running) return
    var modes = []
    Store.VISUAL_GROUPS.forEach(function(group) { group.options.forEach(function(option) { modes.push(option.id) }) })
    var index = modes.indexOf(win.vizConfig.visual)
    var next = modes[(index + direction + modes.length) % modes.length]
    // Keep the bar as the sole settings writer, including desktop shortcuts.
    visualCommand.command = ["omarchy-shell", "org.omaviz.visualizer", "selectVisual", next]
    visualCommand.running = true
  }
  Shortcut { sequence: "Ctrl+Right"; onActivated: win.cycleVisual(1) }
  Shortcut { sequence: "Ctrl+Left"; onActivated: win.cycleVisual(-1) }

  // Heartbeats have their own file: this window only READS settings.
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
    if (!v) { win._closing = true }
    desktopState.setText("[desktop]\nactive = " + v + "\nheartbeat = " + Date.now() + "\n")
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
    // Reload asynchronously; onLoaded applies the completed snapshot.
    interval: 250; repeat: true; running: !win._closing
    onTriggered: { desktopState.reload() }
  }

  IpcHandler {
    target: "omaviz-desktop"
    function status(): string {
      return JSON.stringify({visual: win.vizConfig.visual, colorMode: win.vizConfig.colorMode, siriTravel: win.vizConfig.siriTravel, siriClassic: win.vizConfig.siriClassic, enabled: win.vizConfig.enabled,
        waveSamples: win.spectrumWave.length, configPath: win.settingsPath, engineRunning: bridge.started, closing: win._closing,
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
