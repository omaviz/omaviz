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
  property bool spectrumSilent: true
  property bool detachedRunning: false
  readonly property bool paused: Model.isPaused(root.config.desktopActive === true, root.detachedRunning)
  readonly property int barCount: Math.max(8, (root.config && root.config.bands !== undefined) ? root.config.bands : 32)
  property var barModel: buildBarModel(root.barCount)
  function buildBarModel(n) { var a = []; for (var i = 0; i < n; i++) a.push(i); return a }
  onBarCountChanged: root.barModel = buildBarModel(root.barCount)

  function getBarValue(index) {
    var bands = root.spectrumBands
    if (!bands || bands.length === 0) return 0
    var sens = (root.config && root.config.sensitivity !== undefined) ? root.config.sensitivity : 1.0
    var bandIndex = Math.floor(index * bands.length / root.barCount)
    bandIndex = Math.min(bandIndex, bands.length - 1)
    return Math.min(1, bands[bandIndex] * sens)
  }

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
    command: [root.engineBin]
    stdout: SplitParser {
      onRead: function(data) {
        if (root.paused) return
        var lines = String(data).split("\n")
        for (var i = 0; i < lines.length; i++) {
          var line = lines[i].trim()
          if (line) Model.parseSpectrumLine(line)
        }
        root.spectrumBands = Model.spectrumData.bands
        root.spectrumSilent = Model.spectrumData.silent
      }
    }
    onExited: function(code, status) {
      if (root._bridgeRetries < 10) { root._bridgeRetries++; bridgeRetryTimer.restart() }
    }
  }

  property int _bridgeRetries: 0
  Timer { id: bridgeRetryTimer; interval: 1500; repeat: false; onTriggered: { spectrumProc.running = true } }

  Process {
    id: detachProc
    running: false
    stdout: StdioCollector { onDataChanged: function() {} }
    onExited: function(code, status) {
      root.detachedRunning = false
      if (root.config.desktopActive === true) root.writeDesktopActive(false)
    }
  }

  function detach() {
    if (root.config.desktopActive === true) {
      detachProc.running = false
      root.detachedRunning = false
      root.writeDesktopActive(false)
    } else {
      detachProc.command = ["quickshell", "-p", root.pluginDir + "/Desktop.qml"]
      root.writeDesktopActive(true)
      root.detachedRunning = true
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
      if (root.config.desktopActive === true && !detachProc.running) {
        root.writeDesktopActive(false)
      }
    }
    onFileChanged: root.config = Model.readConfigFromText(text())
    onLoadFailed: root.config = Model.defaultConfig()
  }

  FileView {
    id: detachConfigWrite
    path: Model.configPath
    watchChanges: false
    printErrors: false
    Component.onCompleted: reload()
  }
  function writeDesktopActive(value) {
    var txt = Model.writeConfigKey(detachConfigWrite.text(), "desktop", "active", value ? "true" : "false")
    detachConfigWrite.setText(txt)
    root.config = Model.readConfigFromText(txt)
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
    visible: !paused
    bar: root.bar
    tooltipText: root.paused ? "Omaviz — desktop window open" : (root.spectrumSilent ? "Omaviz — no audio" : "Omaviz — click for settings, double-click for desktop")
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
      color: Qt.rgba(0.08, 0.08, 0.10, 0.75)
      border.width: 1
      border.color: Qt.rgba(0.20, 0.20, 0.25, 0.50)

      Item {
        anchors.fill: parent
        anchors.margins: 4

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
              if (!root.config.colorSync) {
                var botS2 = String(root.config.themeBottom || "")
                if (botS2 === "undefined" || botS2 === "null" || botS2 === "") botS2 = "#e68e0d"
                var bot2 = Qt.color(botS2)
                var r = bot2.r + (1.0 - bot2.r) * v
                var g = bot2.g + (1.0 - bot2.g) * v
                var b = bot2.b + (1.0 - bot2.b) * v
                return Qt.rgba(r, g, b, 1.0)
              }
              var botS = String(root.config.themeBottom || "")
              var topS = String(root.config.themeTop || "")
              if (botS === "undefined" || botS === "null" || botS === "") botS = "#e68e0d"
              if (topS === "undefined" || topS === "null" || topS === "") topS = "#f59e0b"
              var bot = Qt.color(botS)
              var top = Qt.color(topS)
              var r3 = Math.round((bot.r + (top.r - bot.r) * v) * 255)
              var g3 = Math.round((bot.g + (top.g - bot.g) * v) * 255)
              var b3 = Math.round((bot.b + (top.b - bot.b) * v) * 255)
              return "rgb(" + r3 + "," + g3 + "," + b3 + ")"
            }

            Behavior on height { NumberAnimation { duration: 70; easing.type: Easing.OutCubic } }
          }
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
    function open() { root.open() }
    function close() { root.close() }
    function toggle() { root.toggle() }
    function show() { root.open() }
    function hide() { root.close() }
    function refresh() { visualsProc.refresh() }
  }
}
