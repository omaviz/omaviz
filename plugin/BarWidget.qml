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
  property var visuals: []
  property var spectrumBands: []
  property var spectrumWave: []
  property bool spectrumSilent: true
  // Liveness lease: true only if the flag is set AND the heartbeat is fresh.
  // A stranded active=true (crash, kill -9, old code) self-heals within ~6s.
  property bool desktopLive: false
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

  // Shared truth: config desktop.active decides mini visibility,
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
      root.config = Model.readConfigFromText(text())
      root.refreshDesktopLive()
    }
    onFileChanged: {
      root.config = Model.readConfigFromText(text())
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
    var txt = Model.writeConfigKey(configFile.text(), "desktop", "active", value ? "true" : "false")
    detachConfigWrite.setText(txt)
    root.config = Model.readConfigFromText(txt)
    root.refreshDesktopLive()
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
  function writeVizOptions(key1, value1, key2, value2) {
    // Multi-key single write: two sequential setText calls race on the same
    // stale base text and the second clobbers the first (e.g. Spikes+Fire).
    // Apply both keys to ONE base text, then a single setText.
    var txt = configFile.text()
    txt = Model.writeConfigKey(txt, "desktop", key1, vizVal(value1))
    if (key2) txt = Model.writeConfigKey(txt, "desktop", key2, vizVal(value2))
    detachConfigWrite.setText(txt)
    root.config = Model.readConfigFromText(txt)
    root.refreshDesktopLive()
  }
  function vizVal(value) {
    if (typeof value === "boolean") return value ? "true" : "false"
    return value
  }
  function writeDesktopBeat() {
    var txt = Model.writeConfigKey(configFile.text(), "desktop", "heartbeat", String(Date.now()))
    detachConfigWrite.setText(txt)
    root.config = Model.readConfigFromText(txt)
    root.refreshDesktopLive()
  }

  Process {
    id: visualsProc
    running: false
    command: ["bash", "-c",
      "for f in " + Util.shellQuote(Model.visualsDir) + "/*.toml; do " +
      "[ -f \"$f\" ] && printf '%s\\0%s\\0' \"$f\" \"$(cat \"$f\" 2>/dev/null)\"; done"]

    function refresh() { if (!running) running = true }

    stdout: SplitParser {
      onRead: function(data) {
        var chunks = String(data).split("\0")
        var contents = []
        for (var i = 0; i + 1 < chunks.length; i += 2) {
          if (chunks[i]) contents.push({ path: chunks[i], text: chunks[i + 1] || "" })
        }
        root.visuals = Model.discoverVisualsFromText(contents)
      }
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    // Shared flag + fresh heartbeat: hidden whenever a LIVE desktop
    // window is open, regardless of which path launched it.
    visible: !root.desktopLive
    bar: root.bar
    tooltipText: root.spectrumSilent ? "Omaviz — no audio" : "Omaviz — click for settings, double-click for desktop"
    text: ""
    hasVisualContent: true

    property double lastClickTime: 0
    onPressed: function(b) {
      if (b === Qt.LeftButton) {
        var now = new Date().getTime()
        if (now - lastClickTime < 300) {
          root.detach()
        } else {
          root.toggle()
        }
        lastClickTime = now
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
      VisualCanvas {
        anchors.fill: parent
        anchors.margins: root.config.spikes === true ? 0 : 4
        bands: root.spectrumBands
        silent: root.spectrumSilent
        visual: "Bars"
        style: root.config.style || "Classic"
        colorSync: root.config.colorSync === true
        barCount: root.barCount
        colourScheme: 0
        // Rendered gap follows config (same value that sizes the container).
        gapPx: Math.min(6, Math.max(0, root.barGap))
        minBarHeight: 0
        peaks: root.config.peaks !== false
        peakFalloff: root.config.peakFalloff ?? 0.5
        spikes: root.config.spikes === true
        fire: root.config.fire === true
        // Stacks stay off in the mini (segments need taller bars to read).
        splits: false
        // Mini holds 32 bars even in spikes (downsampled from the 128 feed).
        spikeBars: 32
        sensitivity: root.config.sensitivity ?? 1.0
        // colorSync follows the LIVE shell accent; otherwise config colors.
        themeBottom: root.config.colorSync === true ? Qt.darker(Color.accent, 1.3) : (root.config.themeBottom || "#e68e0d")
        themeTop: root.config.colorSync === true ? Color.accent : (root.config.themeTop || "#f59e0b")
        wave: root.spectrumWave
        dots: root.config.dots !== false
        reflect: false
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
    function refresh() { visualsProc.refresh() }
  }
}
