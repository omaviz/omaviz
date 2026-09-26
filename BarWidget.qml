import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "ModelStore.js" as Store

BarWidget {
  id: root
  moduleName: "org.omaviz.visualizer"

  // Reactive config from Store (single source of truth)
  property var config: Store.get("")
  property bool _ready: false

  Component.onCompleted: {
    root._ready = true
    root.snapThemeColors()
    // Initialize config from Store
    root.config = Store.get("")
    // Subscribe to Store changes
    Store.onChanged("mini.colorSync", function(v) { root.config.mini.colorSync = v })
    Store.onChanged("desktop.themeBottom", function(v) { root.config.desktop.themeBottom = v })
    Store.onChanged("desktop.themeTop", function(v) { root.config.desktop.themeTop = v })
    Store.onChanged("desktop.themeAccent", function(v) { root.config.desktop.themeAccent = v })
    Store.onChanged("desktop.barColorCustom", function(v) { root.config.desktop.barColorCustom = v })
    Store.onChanged("desktop.barColorFrom", function(v) { root.config.desktop.barColorFrom = v })
    Store.onChanged("desktop.barColorTo", function(v) { root.config.desktop.barColorTo = v })
    Store.onChanged("desktop.peaks", function(v) { root.config.desktop.peaks = v })
    Store.onChanged("desktop.peakFalloff", function(v) { root.config.desktop.peakFalloff = v })
    Store.onChanged("desktop.peakSustainMs", function(v) { root.config.desktop.peakSustainMs = v })
    Store.onChanged("desktop.linearFall", function(v) { root.config.desktop.linearFall = v })
    Store.onChanged("desktop.spikes", function(v) { root.config.desktop.spikes = v })
    Store.onChanged("desktop.fire", function(v) { root.config.desktop.fire = v })
    Store.onChanged("desktop.stacks", function(v) { root.config.desktop.stacks = v })
    Store.onChanged("desktop.scope", function(v) { root.config.desktop.scope = v })
    Store.onChanged("desktop.artwork", function(v) { root.config.desktop.artwork = v })
    Store.onChanged("desktop.reflect", function(v) { root.config.desktop.reflect = v })
    Store.onChanged("desktop.dots", function(v) { root.config.desktop.dots = v })
    Store.onChanged("desktop.scopeThickness", function(v) { root.config.desktop.scopeThickness = v })
    Store.onChanged("desktop.mono", function(v) { root.config.desktop.mono = v })
    Store.onChanged("desktop.minBarHeight", function(v) { root.config.desktop.minBarHeight = v })
    Store.onChanged("audio.sensitivity", function(v) { root.config.audio.sensitivity = v })
    Store.onChanged("audio.bands", function(v) { root.config.audio.bands = v })
    Store.onChanged("mini.gap", function(v) { root.config.mini.gap = v })
    Store.onChanged("mini.widthScale", function(v) { root.config.mini.widthScale = v })
  }

  // Live theme snapshot: persists the current Omarchy accent triple to
  // config whenever the theme changes, so the standalone desktop window
  // (no qs.* context) follows theme switches within its 100ms poll.
  // Writes only on actual change — never a loop (source is Color.accent,
  // not the config being written).
  property color accentSnap: Color.accent
  property string _snappedAccent: ""
  onAccentSnapChanged: root.snapThemeColors()

  function colorHex(c) {
    function h2(v) {
      var s = Math.round(Math.min(1, Math.max(0, v)) * 255).toString(16)
      return s.length === 1 ? "0" + s : s
    }
    return "#" + h2(c.r) + h2(c.g) + h2(c.b)
  }
  function snapThemeColors() {
    if (!root._ready) return
    var top = root.colorHex(Color.accent)
    if (top === root._snappedAccent) return
    root._snappedAccent = top
    var bottom = root.colorHex(Qt.darker(Color.accent, 1.3))
    Store.set("desktop.themeBottom", bottom)
    Store.set("desktop.themeTop", top)
    Store.set("desktop.themeAccent", top)
  }

  property var spectrumBands: []
  property var spectrumWave: []
  property bool spectrumSilent: true
  property bool vizEnabled: true

  // Liveness lease: true only if the flag is set AND the heartbeat is fresh.
  // A stranded active=true (crash, kill -9, old code) self-heals within ~6s.
  property bool desktopLive: false
  // Last-write-wins guard: setText flushes async, so a file re-read in
  // the next ~1.5s would resurrect stale text and clobber the fresh
  // root.config (dropdowns snapping back = select-twice bug).
  property double _lastWriteAt: 0
  property string _lastWriteText: ""
  function noteWrite(txt) {
    root._lastWriteAt = Date.now()
    root._lastWriteText = txt
    root.config = Store.loadFromTOML(txt)
    root.refreshDesktopLive()
  }
  function readGuarded() {
    if (root._lastWriteText !== "" && Date.now() - root._lastWriteAt < 1500)
      return root._lastWriteText
    return configFile.text()
  }
  function refreshDesktopLive() {
    if (!root.vizEnabled) { root.desktopLive = false; return }
    var hb = (root.config && root.config.desktop && root.config.desktop.desktopHeartbeat) || 0
    root.desktopLive = (root.config && root.config.desktop && root.config.desktop.desktopActive === true) && (Date.now() - hb < 6000)
  }
  readonly property int barCount: Math.max(8, (root.config && root.config.audio && root.config.audio.bands !== undefined) ? root.config.audio.bands : 32)

  function applyConfig(text) { root.config = Store.loadFromTOML(text) }

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
    var g = (root.config && root.config.mini && root.config.mini.gap !== undefined) ? +root.config.mini.gap : 1
    return (g === g && g >= 0) ? g : 1
  }
  readonly property real slotW: root.barGap
  readonly property real widthScale: {
    var w = (root.config && root.config.mini && root.config.mini.widthScale !== undefined) ? +root.config.mini.widthScale : 1.5
    return (w === w && w >= 0.5 && w <= 4) ? w : 1.5
  }
  implicitWidth: Math.round(widthScale * (Style.space(2) + root.barCount * (root.slotW + Style.space(2))))
  implicitHeight: Style.space(28)
  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  readonly property string engineBin: Quickshell.env("HOME") + "/.config/omarchy/plugins/" + root.moduleName + "/bin/omaviz-engine"
  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "")

  Process {
    id: spectrumProc
    running: true
    // High-res feed (128 bands): mini downsamples to 32, preview to 64 —
    // both map from rich source detail instead of a coarse 32-band feed.
    // --wave always on (cheap scope feed); engine now outputs raw bands (no fall-mode).
    command: [root.engineBin, "--bands", "128", "--wave"]
    stdout: SplitParser {
      onRead: function(data) {
        if (!root.vizEnabled) return
        var lines = String(data).split("\n")
        for (var i = 0; i < lines.length; i++) {
          var line = lines[i].trim()
          if (line) Store.parseSpectrumLine(line)
        }
        root.spectrumBands = Store.spectrumData.bands
        root.spectrumWave = Store.spectrumData.wave
        root.spectrumSilent = Store.spectrumData.silent
        root.noteSpectrumFrame()
      }
    }
    onExited: function(code, status) {
      if (!root.vizEnabled) return
      // Indefinite backoff retry: engine death must never permanently kill
      // the mini. Interval grows 1.5s → 30s cap; silence shows meanwhile.
      root._bridgeRetries++
      bridgeRetryTimer.interval = Math.min(30000, 1500 * root._bridgeRetries)
      bridgeRetryTimer.restart()
    }
  }

  property int _bridgeRetries: 0
  // Successful frames reset the backoff so the next failure starts fast.
  function noteSpectrumFrame() { root._bridgeRetries = 0 }
  Timer { id: bridgeRetryTimer; interval: 1500; repeat: false; onTriggered: { spectrumProc.running = true } }

  Process {
    id: detachProc
    running: false
    stdout: StdioCollector { onDataChanged: function() {} }
    onExited: function(code, status) {
      // Bar-spawned desktop closed: release the shared flag (Desktop's own
      // onClosing also writes it; last write wins, same value).
      if (root.config && root.config.desktop && root.config.desktop.desktopActive === true) {
        root.writeDesktopActive(false)
      }
    }
  }

  // Shared truth: config desktop.active decides the mini paused-state,
  // so EVERY launch path (bar double-click, app launcher, keybind)
  // converges. detachProc state is only a fallback for close detection.
  // NOTE: do NOT clear desktop.active here based on detachProc —
  // that would fight launcher-opened windows this process didn't spawn.

  function detach() {
    if (root.config && root.config.desktop && root.config.desktop.desktopActive === true) {
      detachProc.running = false
      root.writeDesktopActive(false)
    } else {
      // Close the settings panel before opening desktop
      if (panelLoader.item) panelLoader.item.close()
      detachProc.command = ["quickshell", "-p", root.pluginDir + "/Desktop.qml"]
      root.writeDesktopActive(true)
      root.writeDesktopBeat()
      detachProc.running = false
      detachProc.running = true
    }
  }

  FileView {
    id: configFile
    path: Store.configPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.config = Store.loadFromTOML(root.readGuarded())
      root.refreshDesktopLive()
      // If config file doesn't exist or is empty, write defaults immediately
      if (!configFile.text() || configFile.text().trim() === "") {
        var txt = Store.toTOML()
        root.noteWrite(txt)
        detachConfigWrite.setText(txt)
      }
    }
    onFileChanged: {
      root.config = Store.loadFromTOML(root.readGuarded())
      root.refreshDesktopLive()
    }
    onLoadFailed: {
      root.config = Store.defaultConfig()
      // Write default config if file doesn't exist
      var txt = Store.toTOML()
      root.noteWrite(txt)
      detachConfigWrite.setText(txt)
    }
  }
  // Poll config (watchChanges is unreliable) so shared flags like
  // desktop.active propagate — this is what hides the mini.
  Timer {
    interval: 500; repeat: true; running: true
    onTriggered: { configFile.reload(); root.refreshDesktopLive() }
  }

  FileView {
    id: detachConfigWrite
    path: Store.configPath
    watchChanges: false
    printErrors: false
    Component.onCompleted: reload()
  }

  // Hook Store persistence to our FileView
  var StorePersistRequest = function(txt) {
    detachConfigWrite.setText(txt)
  }

  function writeDesktopActive(value) {
    // Base the write on configFile (reloaded every 500ms), not the
    // write-only view — bounds staleness so concurrent writers can't
    // resurrect each other's flags from ancient caches.
    var txt = Store.toTOML()
    // Manually update the active field in the TOML
    var lines = txt.split("\n")
    var inDesktop = false
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (line === "[desktop]") { inDesktop = true; continue }
      if (line.startsWith("[") && line.endsWith("]")) { inDesktop = false }
      if (inDesktop && line.startsWith("active")) {
        lines[i] = "active = " + (value ? "true" : "false")
        break
      }
    }
    txt = lines.join("\n")
    root.noteWrite(txt)
    detachConfigWrite.setText(txt)
  }

  function writeEnabled(value) {
    var txt = Store.toTOML()
    var lines = txt.split("\n")
    var inDesktop = false
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (line === "[desktop]") { inDesktop = true; continue }
      if (line.startsWith("[") && line.endsWith("]")) { inDesktop = false }
      if (inDesktop && line.startsWith("enabled")) {
        lines[i] = "enabled = " + (value ? "true" : "false")
        break
      }
    }
    txt = lines.join("\n")
    root.noteWrite(txt)
    detachConfigWrite.setText(txt)
    root.vizEnabled = value
    if (value) {
      // ON: restart engine
      spectrumProc.running = true
      // Clear desktop lease so it can be re-opened
      root.refreshDesktopLive()
    } else {
      // OFF: stop engine, close desktop immediately
      spectrumProc.running = false
      // Immediately mark desktop as not live (override 6s lease)
      root.desktopLive = false
      // Clear bands so mini shows floor
      root.spectrumBands = []
      root.spectrumWave = []
      root.spectrumSilent = true
      // Clear stale spectrum data
      Store.spectrumData.bands = []
      Store.spectrumData.wave = []
      Store.spectrumData.silent = true
      if (root.config && root.config.desktop && root.config.desktop.desktopActive === true) {
        detachProc.running = false
        root.writeDesktopActive(false)
      }
      // Force config reload so panel picks up enabled=false immediately
      configFile.reload()
    }
  }

  function writeVizOption(key, value) {
    Store.set("desktop." + key, value)
  }
  function writeEngineOption(key, value) {
    writeVizOption(key, value)
    // Engine no longer needs restart for fall-mode (removed)
    // but restart for band count changes
    if (key === "bands") {
      spectrumProc.running = false
      spectrumProc.running = true
    }
  }
  function writeAudioOption(key, value) {
    Store.set("audio." + key, value)
  }
  function vizVal(value) {
    if (typeof value === "boolean") return value ? "true" : "false"
    return value
  }
  function writeDesktopBeat() {
    var txt = Store.toTOML()
    var lines = txt.split("\n")
    var inDesktop = false
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (line === "[desktop]") { inDesktop = true; continue }
      if (line.startsWith("[") && line.endsWith("]")) { inDesktop = false }
      if (inDesktop && line.startsWith("heartbeat")) {
        lines[i] = "heartbeat = \"" + String(Date.now()) + "\""
        break
      }
    }
    txt = lines.join("\n")
    detachConfigWrite.setText(txt)
    root.noteWrite(txt)
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    // Option 1: the mini stays in the bar while a desktop window is open,
    // but renders a paused floor (no animation, bars at bottom) instead
    // of hiding — settings stay one click away, no round-trip.
    bar: root.bar
    tooltipText: {
      var viz = root.config && root.config.desktop && root.config.desktop.scope === true ? "Oscilloscope" : "Spectrum"
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
      color: root.config && root.config.desktop && root.config.desktop.spikes === true ? "transparent" : Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.82)
      // Spikes run borderless — the dense spectrum sits directly on the bar.
      border.width: root.config && root.config.desktop && root.config.desktop.spikes === true ? 0 : 1
      border.color: Qt.rgba(0.20, 0.20, 0.25, 0.50)

      // One shared renderer everywhere: mini uses the same VisualCanvas
      // as preview/desktop, so spikes/splits/fire/peaks look identical.
      DotsCanvas {
        anchors.fill: parent
        anchors.margins: root.config && root.config.desktop && root.config.desktop.spikes === true ? 0 : 4
        visible: (root.config && root.config.desktop && root.config.desktop.dots !== false) && !root.desktopLive
      }
      VisualCanvas {
        anchors.fill: parent
        anchors.margins: root.config && root.config.desktop && root.config.desktop.spikes === true ? 0 : 4
        dots: false   // static underlay above (per-frame dots = 34K rects)
        bands: root.desktopLive ? [] : root.spectrumBands
        silent: root.desktopLive ? true : root.spectrumSilent
        visual: root.config && root.config.desktop && root.config.desktop.scope === true ? "Oscilloscope" : "Bars"
        artMode: root.config && root.config.desktop && root.config.desktop.artMode === true
        colorSync: root.config && root.config.mini && root.config.mini.colorSync === true
        barCount: root.barCount
        // Rendered gap follows config (same value that sizes the container).
        gapPx: Math.min(6, Math.max(0, root.barGap))
        peaks: root.config && root.config.desktop && root.config.desktop.peaks !== false
        peakFalloff: root.config && root.config.desktop ? (root.config.desktop.peakFalloff ?? 0.5) : 0.5
        peakSustainMs: root.config && root.config.desktop ? (root.config.desktop.peakSustainMs ?? 100) : 100
        spikes: root.config && root.config.desktop && root.config.desktop.spikes === true
        fire: root.config && root.config.desktop && root.config.desktop.fire === true
        // Stacks stay off in the mini (segments need taller bars to read).
        stacks: false
        // Mini holds 32 bars even in spikes (downsampled from the 128 feed).
        spikeBars: 32
        sensitivity: root.config && root.config.audio ? (root.config.audio.sensitivity ?? 1.0) : 1.0
        // Bar color: custom From→To wins; otherwise LIVE theme accent
        // (Theme mode always follows the Omarchy theme — no stale snapshot).
        barColorCustom: root.config && root.config.desktop && root.config.desktop.barColorCustom === true
        barColorFrom: root.config && root.config.desktop ? (root.config.desktop.barColorFrom || "#e68e0d") : "#e68e0d"
        barColorTo: root.config && root.config.desktop ? (root.config.desktop.barColorTo || "#f59e0b") : "#f59e0b"
        themeBottom: root.config && root.config.desktop ? (root.config.desktop.themeBottom || Qt.darker(Color.accent, 1.3)) : Qt.darker(Color.accent, 1.3)
        themeTop: root.config && root.config.desktop ? (root.config.desktop.themeTop || Color.accent) : Color.accent
        wave: root.desktopLive ? [] : root.spectrumWave
        reflect: false
        // Mono: B&W bars by theme luminance (black on light, white on dark).
        mono: root.config && root.config.desktop && root.config.desktop.mono === true
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