import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Omaviz spectrum bar widget (v2).
// Single bar-widget kind; the panel is loaded internally via Loader
// (clock-plugin pattern). Left-click opens the settings panel.
// The bar renders the live spectrum from the daemon via the
// omaviz-spectrum-bridge helper process.

BarWidget {
  id: root
  moduleName: "org.omaviz.visualizer"

  // ---- Live state (declared on root so QML bindings track changes) ----
  property var config: Model.defaultConfig()
  property var visuals: []
  property var spectrumBands: []
  property bool spectrumSilent: true
  // Mini player pauses (freezes + dims) while the detached desktop window is open.
  readonly property bool paused: root.config.desktopActive === true
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

  // ---- Spectrum reader: bridge binary -> JSON lines on stdout ----
  Process {
    id: spectrumProc
    running: true
    command: ["/home/kishan/.local/bin/omaviz-spectrum-bridge"]
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
  }

  // ---- Config reader (daemon writes ~/.config/omaviz/config.toml) ----
  FileView {
    id: configFile
    path: Model.configPath
    watchChanges: true
    printErrors: false
    onLoaded: root.config = Model.readConfigFromText(text())
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
            if (root.paused) {
              return Util.alpha(root.bar ? root.bar.foreground : Color.foreground, 0.08)
            }
            if (root.spectrumSilent || root.spectrumBands.length === 0) {
              return Util.alpha(root.bar ? root.bar.foreground : Color.foreground, 0.12)
            }
            var v = Math.min(1, Math.max(0, value))
            if (root.config.style === "fire") {
              // winamp-style warm flame: red at base -> yellow at tip
              var r = Math.round(255)
              var g = Math.round(80 + v * 175)
              var b = Math.round(20 + v * 60)
              return "rgba(" + r + "," + g + "," + b + ",1)"
            }
            if (root.config.colorSync) {
              if (v < 0.33) return "#2a9df4"
              if (v < 0.66) return "#9b5de5"
              return "#f15bb5"
            }
            var base = root.bar ? root.bar.foreground : Color.foreground
            return Util.alpha(base, 0.25 + v * 0.75)
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
