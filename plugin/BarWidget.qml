import QtQuick
import Quickshell
import Quickshell.Io
// qs.Commons provides the singleton Style/Util (used for Style.space,
// Util.shellQuote); qs.Ui is used by the panel loaded via panelLoader.
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Omaviz spectrum bar widget (v7).
// Single bar-widget kind; the panel is loaded internally via Loader
// (clock-plugin pattern). Left-click opens the settings panel.
// The bar renders the live spectrum from the bundled omaviz-engine
// (plugin-local bin/), spawned by this widget. No daemon, no socket.

BarWidget {
  id: root
  moduleName: "org.omaviz.visualizer"

  // ---- Live state (declared on root so QML bindings track changes) ----
  property var config: Model.defaultConfig()
  property var visuals: []
  property var spectrumBands: []
  property bool spectrumSilent: true
  // The detached desktop window was removed (violated the omarchy spec's
  // "never start a second Quickshell process for a plugin" rule and the user's
  // explicit instruction). With no detach, the mini player is always live.
  readonly property bool paused: false
  readonly property int barCount: Math.max(
    8, (root.config && root.config.bands !== undefined) ? root.config.bands : 32)
  // T-028 (corrected): render the spectrum as a unicode block-char ticker in
  // WidgetButton.text (WidgetButton ONLY paints `text` — a nested Item/Repeater
  // is never rendered, and with text:'' the button is ~12px so the spectrum
  // spills outside the clip and vanishes). Each of `barCount` columns maps its
  // band energy (0..1, sensitivity-applied) to one of the 8 block glyphs
  // ▁▂▃▄▅▆▇█. Called from the button text binding so it re-runs every frame as
  // root.spectrumBands updates.
  readonly property string BLOCKS: "▁▂▃▄▅▆▇█"
  function spectrumText() {
    var bands = root.spectrumBands
    if (!bands || bands.length === 0) return ""
    var chars = root.BLOCKS
    var n = root.barCount
    var sens = (root.config && root.config.sensitivity !== undefined)
      ? root.config.sensitivity : 1.0
    var out = ""
    for (var i = 0; i < n; i++) {
      var bandIndex = Math.min(bands.length - 1, Math.floor(i * bands.length / n))
      var v = Math.min(1, bands[bandIndex] * sens)
      var level = Math.round(v * 7)   // 0..7 -> ▁..█
      out += chars.charAt(level)
    }
    return out
  }

  // Allow the settings panel (loaded in the same QML process) to push a new
  // config immediately after a write, so pause / color-sync propagate without
  // depending on cross-FileView disk-watch timing.
  function applyConfig(text) { root.config = Model.readConfigFromText(text) }

  // ---- Panel lifecycle contract (required by Bar.findPanelWidget) ----
  readonly property bool opened: panelLoader.item
    ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var t = panelLoader.item
    if (!t) return
    if ("bar" in t) t.bar = root.bar
    if ("anchorItem" in t) t.anchorItem = button
    if ("hostWidget" in t) t.hostWidget = root
    if ("settings" in t) t.settings = root.settings
  }

  // ---- Sizing ----
  // T-028 (corrected): WidgetButton only paints `text`, so we size from the
  // unicode spectrum ticker in WidgetButton.text. The shell WidgetButton derives
  // its implicitWidth from that text (Math.max(12, label.implicitWidth+...)), so
  // the bar allocates a slot that fits the live spectrum — no manual geometry.
  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  // ---- Spectrum reader: bundled omaviz-engine (plugin-local) -> JSON lines ----
  readonly property string engineBin:
    Quickshell.env("HOME") + "/.config/omarchy/plugins/"
    + root.moduleName + "/bin/omaviz-engine"
  Process {
    id: spectrumProc
    running: true
    command: [root.engineBin]
    stdout: SplitParser {
      onRead: function(data) {
        if (root.paused) return   // freeze the mini player while detached (#7)
        var lines = String(data).split("\n")
        for (var i = 0; i < lines.length; i++) {
          var line = lines[i].trim()
          if (line) Model.parseSpectrumLine(line)
        }
        root.spectrumBands = Model.spectrumData.bands
        root.spectrumSilent = Model.spectrumData.silent
      }
    }
    // Self-heal across reboots / engine restarts: if the engine exits, retry a
    // few times so the mini comes up on its own instead of staying dead.
    onExited: function(code, status) {
      if (root._bridgeRetries < 10) {
        root._bridgeRetries++
        bridgeRetryTimer.restart()
      }
    }
  }

  property int _bridgeRetries: 0
  Timer {
    id: bridgeRetryTimer
    interval: 1500; repeat: false
    onTriggered: { spectrumProc.running = true }
  }

  // ---- Config reader (daemon writes ~/.config/omaviz/config.toml) ----
  FileView {
    id: configFile
    path: Model.configPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.config = Model.readConfigFromText(text())
    }
    onFileChanged: root.config = Model.readConfigFromText(text())
    onLoadFailed: root.config = Model.defaultConfig()
  }

  // ---- Visual enumeration from ~/.config/omaviz/visuals/*.toml ----
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
    // T-028 (corrected): WidgetButton ONLY renders `text`. We feed it the live
    // unicode block-char spectrum (root.spectrumText), rebuilt every frame as
    // spectrumBands changes. The shell WidgetButton sizes itself from this text.
    bar: root.bar
    tooltipText: root.spectrumSilent ? "Omaviz — no audio" : "Omaviz — click to configure"
    text: root.spectrumText()
    hasVisualContent: true

    // Click contract (user's explicit, repeated instruction):
    //   1. left-click  -> open the SETTINGS PANEL (root.toggle())
    //   2. NO right-click behavior of any kind.
    // The detached desktop window (a 2nd Quickshell process) was removed:
    // it violated both the user's stated preference and the omarchy spec
    // ("never start a second Quickshell process for a plugin"). The only
    // interaction is left-click -> settings panel.
    onPressed: function(b) {
      if (b === Qt.LeftButton) root.toggle()
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
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function refresh(): void { visualsProc.refresh() }
  }
}
