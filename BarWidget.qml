import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "ModelStore.js" as Store

BarWidget {
  id: root
  moduleName: "org.omaviz.visualizer"

  readonly property var config: settingsDocument.config
  SettingsDocument {
    id: settingsDocument
    writable: true
    onReadyChanged: if (ready) root.snapThemeColors()
    onSettled: {
      if (root._exitRequested && root.config.enabled === false) {
        root._exitRequested = false
        exitProc.running = true
      }
    }
    onErrorChanged: if (error) root._exitRequested = false
  }
  property bool _exitRequested: false
  Process {
    id: exitProc
    command: ["omarchy", "plugin", "disable", root.moduleName]
    onExited: function(code) {
      if (code !== 0) console.warn("omaviz: could not disable plugin (exit " + code + ")")
    }
  }
  function requestExit() {
    if (root._exitRequested || exitProc.running) return
    root._exitRequested = true
    if (!settingsDocument.ready) { root._exitRequested = false; return }
    root.writeEnabled(false)
    if (root.config.enabled === false && settingsDocument.queue.desired === null &&
        settingsDocument.queue.inFlight === null && !settingsDocument.queue.awaitingRead) {
      root._exitRequested = false
      exitProc.running = true
    }
  }
  // Live theme snapshot: persists the current Omarchy accent triple to
  // config whenever the theme changes, so the standalone desktop window
  // (no qs.* context) follows theme switches within its 100ms poll.
  // Writes only on actual change — never a loop (source is Color.accent,
  // not the config being written).
  property color accentSnap: Color.accent
  property string _snappedAccent: ""
  // _ready gates the snapshot until BarWidget (incl. the write-only
  // FileView) completes: setText during construction warns "no path"
  // and drops the write.
  property bool _ready: false
  Component.onCompleted: { root._ready = true; root.snapThemeColors() }
  onAccentSnapChanged: root.snapThemeColors()
  onConfigChanged: Qt.callLater(root.snapThemeColors)
  function colorHex(c) {
    function h2(v) {
      var s = Math.round(Math.min(1, Math.max(0, v)) * 255).toString(16)
      return s.length === 1 ? "0" + s : s
    }
    return "#" + h2(c.r) + h2(c.g) + h2(c.b)
  }
  function snapThemeColors() {
    if (!root._ready) return
    if (!root.config) return
    var top = root.colorHex(Color.accent)
    if (top === root._snappedAccent) return
    if (!settingsDocument.ready) return
    var curTop = root.config.themeAccent || ""
    // File already fresh: adopt without writing (avoids a mount-time
    // setText, which FileView can drop with a "no path" warning).
    if (curTop === top) { root._snappedAccent = top; return }
    var bottom = root.colorHex(Qt.darker(Color.accent, 1.3))
    root._snappedAccent = top
    root.writeVizOptions3("theme_bottom", bottom, "theme_top", top, "theme_accent", top)
  }
  readonly property var spectrumBands: spectrumFeed.bands
  readonly property var spectrumWave: spectrumFeed.wave
  readonly property bool spectrumSilent: spectrumFeed.silent
  readonly property bool vizEnabled: root.config.enabled !== false
  property bool desktopLive: false
  function refreshDesktopLive() {
    if (!root.vizEnabled) { root.desktopLive = false; return }
    var state = desktopState.text()
    var hb = Number(Store.readTomlValue(state, "desktop", "heartbeat") || 0)
    root.desktopLive = Store.isDesktopActiveFromText(state) && hb <= Date.now() && Date.now() - hb < 6000
  }
  readonly property int barCount: Math.max(8, (root.config && root.config.bands !== undefined) ? root.config.bands : 32)


  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    var t = panelLoader.item
    if (!t) return
    if ("bar" in t) t.bar = root.bar
    if ("anchorItem" in t) t.anchorItem = button
    if ("hostWidget" in t) t.hostWidget = root
    if ("settings" in t) t.settings = root.settings
  }

  readonly property real barGap: {
    var g = (root.config && root.config.gap !== undefined) ? +root.config.gap : 3
    return (g === g && g >= 0) ? g : 3
  }
  readonly property real slotW: root.barGap
  readonly property real widthScale: {
    var w = (root.config && root.config.widthScale !== undefined) ? +root.config.widthScale : 1
    return (w === w && w >= 0.5 && w <= 4) ? w : 1
  }
  implicitWidth: Math.round(widthScale * (Style.space(2) + root.barCount * (root.slotW + Style.space(2))))
  implicitHeight: Style.space(28)
  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  readonly property string engineBin: Store.engineBin
  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "")

  EngineFeed {
    id: spectrumFeed
    active: root.vizEnabled && settingsDocument.ready && (!root.desktopLive || root.opened)
    waveEnabled: root.config.scope === true
  }
  readonly property string sourceLabel: Store.sourceLabel(spectrumFeed.source)

  Process {
    id: detachProc
    running: false
    stdout: StdioCollector { onDataChanged: function() {} }
  }

  // Runtime liveness is separate from persistent settings. Never infer it
  // from detachProc: launcher-opened windows are not owned by this process.

  function detach() {
    if (root.desktopLive) {
      detachProc.running = false
      root.writeDesktopActive(false)
    } else {
      // Close the settings panel before opening desktop
      if (panelLoader.item) panelLoader.item.close()
      detachProc.command = ["quickshell", "-p", root.pluginDir + "/Desktop.qml"]
      root.writeDesktopActive(true)
      detachProc.running = false
      detachProc.running = true
    }
  }

  Timer {
    interval: 500; repeat: true; running: true
    onTriggered: { desktopState.reload(); root.refreshDesktopLive() }
  }

  FileView {
    id: desktopState
    path: Store.desktopStatePath
    watchChanges: true
    printErrors: false
    onLoaded: root.refreshDesktopLive()
    onFileChanged: reload()
  }
  function writeDesktopActive(value) {
    // This file contains only a lease; it can never clobber user settings.
    desktopState.setText("[desktop]\nactive = " + value + "\nheartbeat = " + Date.now() + "\n")
    root.desktopLive = value && root.vizEnabled
  }

  function writeEnabled(value) {
    settingsDocument.patch("desktop", { enabled: value })
    if (!value) { detachProc.running = false; root.writeDesktopActive(false) }
  }
  function writeVizOption(key, value) {
    var values = {}; values[key] = value
    settingsDocument.patch("desktop", values)
  }
  function writeEngineOption(key, value) { writeVizOption(key, value) }
  function writeAudioOption(key, value) {
    var values = {}; values[key] = value
    settingsDocument.patch("audio", values)
  }
  function writeVizOptions(key1, value1, key2, value2) {
    writeVizOptions3(key1, value1, key2, value2)
  }
  function writeVizOptions3(key1, value1, key2, value2, key3, value3, key4, value4) {
    var values = {}; values[key1] = value1
    if (key2) values[key2] = value2
    if (key3) values[key3] = value3
    if (key4) values[key4] = value4
    settingsDocument.patch("desktop", values)
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    // Option 1: the mini stays in the bar while a desktop window is open,
    // but renders a paused floor (no animation, bars at bottom) instead
    // of hiding — settings stay one click away, no round-trip.
    bar: root.bar
    tooltipText: {
      var viz = root.config.scope === true ? "Oscilloscope" : "Spectrum"
      return "Omaviz — " + viz
    }
    text: ""
    hasVisualContent: true

    onPressed: function(b) {
      if (b === Qt.LeftButton) {
        // Ensure panel is injected before trying to open/close
        if (!panelLoader.item) root.injectPanel()
        if (root.opened) root.close()
        else root.open()
      }
    }

    Rectangle {
      id: miniBg
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
      anchors.right: parent.right
      height: parent.height * 0.90
      // Theme-aware container: tracks the shell background so it reads
      // correctly on light and dark themes (dark theme ≈ previous look).
      color: root.config.spikes === true ? "transparent" : Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.82)
      // Spikes run borderless — the dense spectrum sits directly on the bar.
      border.width: root.config.spikes === true ? 0 : 1
      border.color: Qt.rgba(0.20, 0.20, 0.25, 0.50)

      // One shared renderer everywhere: mini uses the same VisualCanvas
      // as preview/desktop, so spikes/splits/fire/peaks look identical.
      DotsCanvas {
        anchors.fill: parent
        anchors.margins: root.config.spikes === true ? 0 : 4
        visible: root.config.dots !== false && !root.desktopLive
      }
      VisualCanvas {
        anchors.fill: parent
        anchors.margins: root.config.spikes === true ? 0 : 4
        dots: false   // static underlay above (per-frame dots = 34K rects)
        bands: root.desktopLive ? [] : root.spectrumBands
        silent: root.desktopLive ? true : root.spectrumSilent
        visual: root.config.scope === true ? "Oscilloscope" : "Bars"
        colorSync: root.config.colorSync === true
        barCount: root.barCount
        // Rendered gap follows config (same value that sizes the container).
        gapPx: Math.min(6, Math.max(0, root.barGap))
        peaks: root.config.peaks !== false
        peakFalloff: root.config.peakFalloff ?? 0.1
        peakSustainMs: root.config.peakSustainMs ?? 100
        linearFall: root.config.linearFall !== false
        noiseFloor: 0.02
        spikes: root.config.spikes === true
        fire: root.config.fire === true
        fireColorFrom: root.config.fireColorFrom || "#be1400"
        fireColorTo: root.config.fireColorTo || "#fde047"
        // Stacks stay off in the mini (segments need taller bars to read).
        stacks: false
        // Mini holds 32 bars even in spikes (downsampled from the 128 feed).
        spikeBars: 32
        sensitivity: root.config.sensitivity ?? 1.0
        // Bar color: custom From→To wins; otherwise LIVE theme accent
        // (Theme mode always follows the Omarchy theme — no stale snapshot).
        barColorCustom: root.config.barColorCustom === true
        barColorFrom: root.config.barColorFrom || "#e68e0d"
        barColorTo: root.config.barColorTo || "#f59e0b"
        gradientDir: root.config.barGradientDir || "vertical"
        themeBottom: Qt.darker(Color.accent, 1.3)
        themeTop: Color.accent
        wave: root.desktopLive ? [] : root.spectrumWave
        reflect: false
        // Mono: B&W bars by theme luminance (black on light, white on dark).
        mono: root.config.mono === true
        monoLight: (0.299 * Color.background.r + 0.587 * Color.background.g + 0.114 * Color.background.b) > 0.5
      }
    }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel) }
  }

  IpcHandler {
    target: "org.omaviz.visualizer"
    function open() { root.open() }
    function close() { root.close() }
    function toggle() { root.toggle() }
    function show() { root.open() }
    function hide() { root.close() }
  }
}
