import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "org.omaviz.visualizer"

  property var config: Model.defaultConfig()
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
  onConfigChanged: root.snapThemeColors()
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
    var curTop = Model.readConfigFromText(root.readGuarded()).themeAccent || ""
    // File already fresh: adopt without writing (avoids a mount-time
    // setText, which FileView can drop with a "no path" warning).
    if (curTop === top) { root._snappedAccent = top; return }
    var bottom = root.colorHex(Qt.darker(Color.accent, 1.3))
    root._snappedAccent = top
    root.writeVizOptions3("theme_bottom", bottom, "theme_top", top, "theme_accent", top)
  }
  property var spectrumBands: []
  property var spectrumWave: []
  property bool spectrumSilent: true
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
    root.config = Model.readConfigFromText(txt)
    root.refreshDesktopLive()
  }
  function readGuarded() {
    if (root._lastWriteText !== "" && Date.now() - root._lastWriteAt < 1500)
      return root._lastWriteText
    return configFile.text()
  }
  function refreshDesktopLive() {
    var hb = (root.config && root.config.desktopHeartbeat) || 0
    root.desktopLive = (root.config && root.config.desktopActive === true) && (Date.now() - hb < 6000)
  }
  readonly property int barCount: Math.max(8, (root.config && root.config.bands !== undefined) ? root.config.bands : 32)

  function applyConfig(text) { root.config = Model.readConfigFromText(text) }

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

  readonly property string engineBin: Quickshell.env("HOME") + "/.config/omarchy/plugins/" + root.moduleName + "/bin/omaviz-engine"
  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "")

  Process {
    id: spectrumProc
    running: true
    // High-res feed (128 bands): mini downsamples to 32, preview to 64 —
    // both map from rich source detail instead of a coarse 32-band feed.
    // --wave always on (cheap scope feed); --fall-mode follows config.
    command: [root.engineBin, "--bands", "128", "--wave"].concat(
      root.config.linearFall === true ? ["--fall-mode", "linear"] : [])
    stdout: SplitParser {
      onRead: function(data) {
        var lines = String(data).split("\n")
        for (var i = 0; i < lines.length; i++) {
          var line = lines[i].trim()
          if (line) Model.parseSpectrumLine(line)
        }
        root.spectrumBands = Model.spectrumData.bands
        root.spectrumWave = Model.spectrumData.wave
        root.spectrumSilent = Model.spectrumData.silent
        root.noteSpectrumFrame()
      }
    }
    onExited: function(code, status) {
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
      if (root.config.desktopActive === true) {
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
    if (root.config.desktopActive === true) {
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
    path: Model.configPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.config = Model.readConfigFromText(root.readGuarded())
      root.refreshDesktopLive()
    }
    onFileChanged: {
      root.config = Model.readConfigFromText(root.readGuarded())
      root.refreshDesktopLive()
    }
    onLoadFailed: root.config = Model.defaultConfig()
  }
  // Poll config (watchChanges is unreliable) so shared flags like
  // desktop.active propagate — this is what hides the mini.
  Timer {
    interval: 500; repeat: true; running: true
    onTriggered: { configFile.reload(); root.refreshDesktopLive() }
  }

  FileView {
    id: detachConfigWrite
    path: Model.configPath
    watchChanges: false
    printErrors: false
    Component.onCompleted: reload()
  }
  function writeDesktopActive(value) {
    // Base the write on configFile (reloaded every 500ms), not the
    // write-only view — bounds staleness so concurrent writers can't
    // resurrect each other's flags from ancient caches (#16).
    var txt = Model.writeConfigKey(root.readGuarded(), "desktop", "active", value ? "true" : "false")
    detachConfigWrite.setText(txt)
    root.noteWrite(txt)
  }

  function writeEnabled(value) {
    var txt = Model.writeEnabled(value, root.readGuarded())
    detachConfigWrite.setText(txt)
    root.noteWrite(txt)
    if (value) {
      // ON: restart engine
      spectrumProc.running = true
    } else {
      // OFF: stop engine, close desktop
      spectrumProc.running = false
      if (root.config.desktopActive === true) {
        detachProc.running = false
        root.writeDesktopActive(false)
      }
      // Clear bands so mini shows floor
      root.spectrumBands = []
      root.spectrumWave = []
    }
  }
  function writeVizOption(key, value) {
    writeVizOptions(key, value, null, null)
  }
  // Engine-flag options need a process restart to take effect (CLI args
  // are read at spawn). Restart is cheap (~100ms gap, backoff resets).
  function writeEngineOption(key, value) {
    writeVizOption(key, value)
    spectrumProc.running = false
    spectrumProc.running = true
  }
  // Audio-section options (e.g. sensitivity): same single-write pattern as
  // writeVizOptions but targeting [audio]. Applied QML-side, so every
  // surface picks it up live through the config poll — no restart needed.
  function writeAudioOption(key, value) {
    var txt = Model.writeConfigKey(root.readGuarded(), "audio", key, vizVal(value))
    detachConfigWrite.setText(txt)
    root.noteWrite(txt)
  }
  function writeVizOptions(key1, value1, key2, value2) {
    // Multi-key single write: two sequential setText calls race on the same
    // stale base text and the second clobbers the first (e.g. Spikes+Fire).
    // Apply both keys to ONE base text, then a single setText.
    var txt = root.readGuarded()
    txt = Model.writeConfigKey(txt, "desktop", key1, vizVal(value1))
    if (key2) txt = Model.writeConfigKey(txt, "desktop", key2, vizVal(value2))
    detachConfigWrite.setText(txt)
    root.noteWrite(txt)
  }
  // Three-key single write (preset swatches, theme snapshot): same
  // one-base-text rule as writeVizOptions.
  function writeVizOptions3(key1, value1, key2, value2, key3, value3) {
    var txt = root.readGuarded()
    txt = Model.writeConfigKey(txt, "desktop", key1, vizVal(value1))
    if (key2) txt = Model.writeConfigKey(txt, "desktop", key2, vizVal(value2))
    if (key3) txt = Model.writeConfigKey(txt, "desktop", key3, vizVal(value3))
    detachConfigWrite.setText(txt)
    root.noteWrite(txt)
  }
  function vizVal(value) {
    if (typeof value === "boolean") return value ? "true" : "false"
    return value
  }
  function writeDesktopBeat() {
    var txt = Model.writeConfigKey(root.readGuarded(), "desktop", "heartbeat", String(Date.now()))
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
    tooltipText: "Omaviz"
    text: ""
    hasVisualContent: true

    onPressed: function(b) {
      if (b === Qt.LeftButton) root.toggle()
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
        artMode: root.config.artMode === true
        colorSync: root.config.colorSync === true
        barCount: root.barCount
        // Rendered gap follows config (same value that sizes the container).
        gapPx: Math.min(6, Math.max(0, root.barGap))
        peaks: root.config.peaks !== false
        peakFalloff: root.config.peakFalloff ?? 0.5
        spikes: root.config.spikes === true
        fire: root.config.fire === true
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
