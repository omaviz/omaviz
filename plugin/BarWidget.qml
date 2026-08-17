import QtQuick
import Quickshell
import Quickshell.Io
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
  // Mini player pauses (freezes + dims) while the detached desktop window is
  // open. Derived from BOTH the config flag and the actual detach process
  // state (set by the panel via root.detachedRunning) so a stale
  // desktop.active=true (window killed without onClosing) can never freeze
  // the mini forever. detachedRunning is intentionally writable (NOT readonly)
  // because the Panel assigns it from detach()/detachProc.onExited.
  property bool detachedRunning: false
  readonly property bool paused: Model.isPaused(root.config.desktopActive === true, root.detachedRunning)
  readonly property int barCount: Math.max(
    8, (root.config && root.config.bands !== undefined) ? root.config.bands : 32)
  // Explicit index model so each Repeater delegate gets its band index via
  // modelData (the shell's Repeater does not expose the implicit `index`
  // context property the way stock QtQuick does). Regenerated when barCount
  // changes (e.g. config reload).
  property var barModel: buildBarModel(root.barCount)
  function buildBarModel(n) {
    var a = []
    for (var i = 0; i < n; i++) a.push(i)
    return a
  }
  onBarCountChanged: root.barModel = buildBarModel(root.barCount)

  // Map a bar index to its spectrum value (root scope so the Repeater
  // delegate can resolve it during initialization).
  function getBarValue(index) {
    var bands = root.spectrumBands
    if (!bands || bands.length === 0) return 0
    var sens = (root.config && root.config.sensitivity !== undefined)
      ? root.config.sensitivity : 1.0
    var bandIndex = Math.floor(index * bands.length / root.barCount)
    bandIndex = Math.min(bandIndex, bands.length - 1)
    return Math.min(1, bands[bandIndex] * sens)
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

  // ---- Geometry: claim a dedicated slot in the bar's Row from the
  // spectrum bar count (the button has no text/icon, so it would otherwise
  // collapse to zero and render behind neighbors). ----
  readonly property real slotW: 3
  implicitWidth: Style.space(2) + root.barCount * (root.slotW + Style.space(2))
  implicitHeight: Style.space(28)
  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  // ---- Spectrum reader: bundled omaviz-engine (plugin-local) -> JSON lines ----
  readonly property string engineBin:
    Quickshell.env("HOME") + "/.config/omarchy/plugins/"
    + root.moduleName + "/bin/omaviz-engine"
  // Paths the detached desktop window needs (mirrors Panel's, kept here so the
  // detach Process — which lives on the persistent BarWidget, not the panel —
  // can launch Desktop.qml after the panel closes).
  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "")
  readonly property string shellImportPath: "/usr/share/omarchy/shell"
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

  // ---- Detached desktop-window launcher (lives on the persistent BarWidget) ----
  // Kept on the BarWidget (not the panel) so the window survives the panel
  // closing. detach()/attach() are methods here; the panel button just calls
  // root.hostWidget.detach(). Uses the `environment` property (not an `env`
  // wrapper) so setting running=false terminates the child quickshell
  // directly — that is what makes Attach reliable.
  Process {
    id: detachProc
    running: false
    environment: { "QML2_IMPORT_PATH": "/usr/share/omarchy/shell" }
    stdout: StdioCollector { onDataChanged: function() {} }
    onExited: function(code, status) {
      // Window closed (or launch failed). Resume the mini so it is never
      // left stuck-paused. Clear the in-memory detach flag FIRST (this is the
      // authoritative unpause — it does not depend on the disk write), then
      // reset desktop.active on disk.
      root.detachedRunning = false
      if (root.config.desktopActive === true) root.writeDesktopActive(false)
    }
  }

  // Detach / Attach toggle.
  function detach() {
    if (root.config.desktopActive === true) {
      // Attach: terminate the window if it is running. ALSO reset the flag
      // unconditionally — if the window already died without clearing it
      // (external kill, crash), onExited never fires and the flag would stay
      // stuck as "true", leaving the button frozen on "Attach" with no
      // window to close. Resetting here guarantees we can detach again.
      detachProc.running = false
      root.detachedRunning = false
      root.writeDesktopActive(false)
    } else {
      // Detach: launch the standalone desktop window.
      detachProc.command = ["quickshell", "-p", root.pluginDir + "/Desktop.qml"]
      root.writeDesktopActive(true)
      root.detachedRunning = true
      detachProc.running = false
      detachProc.running = true
    }
  }

  // ---- Config reader (daemon writes ~/.config/omaviz/config.toml) ----
  FileView {
    id: configFile
    path: Model.configPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.config = Model.readConfigFromText(text())
      // Self-heal: if the desktop flag is stuck true but no window is running
      // (e.g. the detach window was killed externally), reset it so the
      // button returns to "Detach" instead of being frozen on "Attach".
      if (root.config.desktopActive === true && !detachProc.running) {
        root.writeDesktopActive(false)
      }
    }
    onFileChanged: root.config = Model.readConfigFromText(text())
    onLoadFailed: root.config = Model.defaultConfig()
  }

  // Writable config view (detach lifecycle writes desktop.active here so the
  // reset does not depend on the panel being open). Same no-watch pattern as
  // the panel's writer to avoid async reverts.
  FileView {
    id: detachConfigWrite
    path: Model.configPath
    watchChanges: false
    printErrors: false
  }
  function writeDesktopActive(value) {
    var txt = Model.writeConfigKey(detachConfigWrite.text(), "desktop", "active", value ? "true" : "false")
    detachConfigWrite.setText(txt)
    root.config = Model.readConfigFromText(txt)
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
    anchors.fill: parent
    bar: root.bar
    tooltipText: root.paused ? "Omaviz — detached (paused)"
                  : (root.spectrumSilent ? "Omaviz — no audio" : "Omaviz — click to configure")
    text: ""
    hasVisualContent: true

    onPressed: function(b) {
      if (b === Qt.LeftButton) root.toggle()
    }

    Item {
      anchors.fill: parent
      anchors.margins: Style.space(4)

      readonly property real slotWidth: Math.max(2,
        (width - Style.space(2) * (root.barCount + 1)) / root.barCount)

      Repeater {
        model: root.barModel

        Rectangle {
          id: bar
          readonly property real value: getBarValue(modelData)

          x: Style.space(2) + modelData * (parent.slotWidth + Style.space(2))
          width: parent.slotWidth
          height: parent.height * value
          y: parent.height - height

          radius: Math.min(width * 0.5, 3)
          color: {
            if (root.config.style === "fire") {
              var v0 = Math.min(1, Math.max(0, value))
              return "rgba(255," + Math.round(80 + v0 * 175) + "," + Math.round(20 + v0 * 60) + ",1)"
            }
            var v = Math.min(1, Math.max(0, value))
            // Default: monochrome (bright, fully visible on dark bar bg).
            if (!root.config.colorSync) {
              // Bright white/light gray at FULL opacity so it's always visible.
              return "rgba(235,240,250,1)"
            }
            // color-sync ON: theme-dominant bottom->top gradient
            var botS = String(root.config.themeBottom || "")
            var topS = String(root.config.themeTop || "")
            if (botS === "undefined" || botS === "null" || botS === "") botS = "#e68e0d"
            if (topS === "undefined" || topS === "null" || topS === "") topS = "#f59e0b"
            var bot = Qt.color(botS)
            var top = Qt.color(topS)
            var r = Math.round((bot.r + (top.r - bot.r) * v) * 255)
            var g = Math.round((bot.g + (top.g - bot.g) * v) * 255)
            var bl = Math.round((bot.b + (top.b - bot.b) * v) * 255)
            return "rgb(" + r + "," + g + "," + bl + ")"
          }

          Behavior on height { NumberAnimation { duration: 70; easing.type: Easing.OutCubic } }
        }
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
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function refresh(): void { visualsProc.refresh() }
  }
}
