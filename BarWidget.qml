import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "ModelStore.js" as Store

BarWidget {
  id: root
  moduleName: "org.omaviz.visualizer"

  readonly property string settingsPath: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/omaviz/config.toml"
  readonly property string leasePath: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/omaviz/desktop-state.toml"
  property var config: Store.defaultConfig()
  readonly property var artworkPalette: artworkColors.colors
  ArtworkColors { id: artworkColors; active: root.config.artworkColors === true && root.config.visual === "Bars" }
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
  property bool _configReady: false
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
    if (!root._ready || !root._configReady) return
    if (!root.config) return
    var top = root.colorHex(Color.accent)
    if (top === root._snappedAccent) return
    var curTop = Store.readConfigFromText(root.readGuarded()).themeAccent || ""
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
  property bool vizEnabled: true

  // Liveness lease: true only if the flag is set AND the heartbeat is fresh.
  // A stranded active=true (crash, kill -9, old code) self-heals within ~6s.
  property bool desktopLive: false
  // Keep optimistic settings until the writer finishes and the reader catches up.
  property string _lastWriteText: ""
  property string _writingText: ""
  property bool _writeBusy: false
  property bool _exitRequested: false
  // The one place config text becomes live state. Everything (panel bindings,
  // the engine, the desktop lease) derives from this, so a value can never be
  // shown that the config does not actually contain.
  function syncFromConfig(txt) {
    root.config = Store.loadFromTOML(txt)
    var on = root.config.enabled !== false
    if (root.vizEnabled !== on) {
      root.vizEnabled = on
      if (!on) {
        root.spectrumBands = []
        root.spectrumWave = []
        Store.spectrumData.bands = []
        Store.spectrumData.wave = []
        Store.spectrumData.silent = true
        root.spectrumSource = ""
      }
    }
    // Scope is a SPAWN-TIME flag (it toggles the engine's `--wave` feed): the
    // process must be bounced when it flips, or Bars mode would keep paying
    // ~0.7KB/line of JSON parse for a snippet it never reads.
    var sc = root.config.visual !== "Bars"
    if (root._lastScope !== sc) {
      root._lastScope = sc
      if (root.wantsFeed()) root.restartSpectrum()
    }
    root.refreshDesktopLive()
    root.syncBarFeed()
  }
  // Bounce the engine without tripping the failure backoff (see onExited).
  function restartSpectrum() {
    if (!root.wantsFeed() || root._restarting || root._intentionalFeedStop) return
    if (!spectrumProc.running) { spectrumProc.running = true; return }
    root._restarting = true
    root.spectrumWave = []
    Store.spectrumData.wave = []
    spectrumProc.running = false
    // Quickshell stops asynchronously. Resume from onExited so rapid
    // mode changes cannot overlap capture processes or reuse old flags.
  }
  function noteWrite(txt) {
    root._lastWriteText = txt
    root.syncFromConfig(txt)
  }
  function readGuarded() {
    if (root._lastWriteText !== "") {
      if (!root._writeBusy && configFile.text() === root._lastWriteText)
        root._lastWriteText = ""
      else return root._lastWriteText
    }
    return configFile.text()
  }
  function refreshDesktopLive() {
    var state = desktopState.text()
    var hb = Number(Store.readTomlValue(state, "desktop", "heartbeat") || 0)
    root.desktopLive = Store.isDesktopActiveFromText(state) && hb <= Date.now() && Date.now() - hb < 6000
  }
  // The detached window has its own capture engine. With the mini hidden and
  // settings closed, a second 128-band process and JSON parser do no work for
  // the user. Resume the bar feed when its preview opens or the desktop leaves.
  function wantsFeed() {
    return !root._exitRequested && root.vizEnabled && (!root.desktopLive || root.opened)
  }
  function syncBarFeed() {
    if (root.wantsFeed()) {
      if (!spectrumProc.running && !root._restarting && !root._intentionalFeedStop) spectrumProc.running = true
    } else {
      bridgeRetryTimer.stop()
      if (spectrumProc.running) {
        root._intentionalFeedStop = true
        spectrumProc.running = false
      }
    }
  }
  onDesktopLiveChanged: root.syncBarFeed()
  onOpenedChanged: root.syncBarFeed()
  readonly property int barCount: Math.max(8, (root.config && root.config.bands !== undefined) ? root.config.bands : 32)
  property string spectrumSource: ""

  function applyConfig(text) { root.syncFromConfig(text) }

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

  Process {
    id: spectrumProc
    running: true
    // High-res feed (128 bands): mini downsamples to 32, preview to 64 —
    // both map from rich source detail instead of a coarse 32-band feed.
    // `--wave` is scope-only (Bars mode never reads the snippet), so it is
    // added only while the oscilloscope is selected; syncFromConfig bounces
    // the process when scope flips. Physics (fall/peaks) is renderer-side, so
    // those are not spawn-time flags.
    command: root.config.visual !== "Bars"
      ? [root.engineBin, "--bands", "128", "--wave"]
      : [root.engineBin, "--bands", "128"]
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
        root.spectrumSource = Store.spectrumData.source || ""
        root.noteSpectrumFrame()
      }
    }
    onExited: function(code, status) {
      if (root._restarting) {
        root._restarting = false
        root.syncBarFeed()
        return
      }
      if (root._intentionalFeedStop) {
        root._intentionalFeedStop = false
        root.syncBarFeed()
        return
      }
      if (!root.wantsFeed()) return
      // Indefinite backoff retry: engine death must never permanently kill
      // the mini. Interval grows 1.5s → 30s cap; silence shows meanwhile.
      root._bridgeRetries++
      bridgeRetryTimer.interval = Math.min(30000, 1500 * root._bridgeRetries)
      bridgeRetryTimer.restart()
    }
  }

  property int _bridgeRetries: 0
  property bool _restarting: false
  property bool _intentionalFeedStop: false
  property bool _lastScope: false
  // Successful frames reset the backoff so the next failure starts fast.
  function noteSpectrumFrame() { root._bridgeRetries = 0 }
  Timer { id: bridgeRetryTimer; interval: 1500; repeat: false; onTriggered: root.syncBarFeed() }

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

  FileView {
    id: configFile
    path: root.settingsPath
    watchChanges: true
    printErrors: false
    onLoaded: { root._configReady = true; root.syncFromConfig(root.readGuarded()) }
    onFileChanged: root.syncFromConfig(root.readGuarded())
    onLoadFailed: { root._configReady = true; if (root._lastWriteText === "") root.syncFromConfig("") }
  }
  // Poll config (watchChanges is unreliable) so shared flags like
  // desktop.active propagate — this is what hides the mini.
  Timer {
    interval: 500; repeat: true; running: true
    onTriggered: { configFile.reload(); desktopState.reload(); root.refreshDesktopLive() }
  }

  FileView {
    id: desktopState
    path: root.leasePath
    watchChanges: true
    printErrors: false
    onLoaded: root.refreshDesktopLive()
    onFileChanged: reload()
  }
  FileView {
    id: detachConfigWrite
    path: root.settingsPath
    watchChanges: false
    printErrors: false
    onSaved: {
      root._writeBusy = false
      if (root._lastWriteText !== root._writingText) root.flushSettings()
      else {
        configFile.reload()
      }
    }
    onSaveFailed: {
      root._writeBusy = false
      root._lastWriteText = ""
      console.warn("omaviz: could not save settings")
      configFile.reload()
    }
  }
  Process {
    id: exitProc
    command: ["omarchy", "plugin", "disable", root.moduleName]
    onExited: function(code) {
      if (code !== 0) console.warn("omaviz: could not disable plugin (exit " + code + ")")
    }
  }
  Timer { id: exitDelay; interval: 350; onTriggered: exitProc.running = true }
  function requestExit() {
    if (root._exitRequested) return
    root._exitRequested = true
    root.close()
    bridgeRetryTimer.stop()
    root._intentionalFeedStop = true
    spectrumProc.running = false
    root.writeDesktopActive(false)
    exitDelay.restart()
  }
  function flushSettings() {
    if (root._writeBusy || root._lastWriteText === "") return
    root._writingText = root._lastWriteText
    root._writeBusy = true
    detachConfigWrite.setText(root._writingText)
  }
  function writeDesktopActive(value) {
    // This file contains only a lease; it can never clobber user settings.
    desktopState.setText("[desktop]\nactive = " + value + "\nheartbeat = " + Date.now() + "\n")
    root.desktopLive = value
  }

  function writeEnabled(value) {
    var txt = Store.writeEnabled(value, root.readGuarded())
    root.noteWrite(txt)            // syncFromConfig flips vizEnabled + engine
    root.flushSettings()
  }
  function writeVizOption(key, value) {
    writeVizOptions(key, value, null, null)
  }
  // Renderer-side options (e.g. linear_fall) apply live through the config
  // poll — no engine restart, since the CLI no longer takes physics flags.
  function writeEngineOption(key, value) {
    writeVizOption(key, value)
  }
  // Audio-section options (e.g. sensitivity): same single-write pattern as
  // writeVizOptions but targeting [audio]. Applied QML-side, so every
  // surface picks it up live through the config poll — no restart needed.
  function writeAudioOption(key, value) {
    var txt = Store.writeConfigKey(root.readGuarded(), "audio", key, value)
    root.noteWrite(txt)
    root.flushSettings()
  }
  function setColorMode(mode) {
    if (["Theme", "Custom", "Artwork", "Flame"].indexOf(mode) < 0) return false
    var options = { fire: mode === "Flame", bar_color_custom: mode === "Custom", artwork_colors: mode === "Artwork" }
    if (mode === "Artwork") options.artwork = true
    root.writeVizMap(options)
    return true
  }
  function writeVizMap(options) {
    var txt = root.readGuarded()
    for (var key in options) txt = Store.writeConfigKey(txt, "desktop", key, options[key])
    root.noteWrite(txt)
    root.flushSettings()
  }
  function writeVizOptions(key1, value1, key2, value2) {
    // Multi-key single write: two sequential setText calls race on the same
    // stale base text and the second clobbers the first (e.g. Spikes+Fire).
    // Apply both keys to ONE base text, then a single setText.
    var txt = root.readGuarded()
    txt = Store.writeConfigKey(txt, "desktop", key1, value1)
    if (key2) txt = Store.writeConfigKey(txt, "desktop", key2, value2)
    root.noteWrite(txt)
    root.flushSettings()
  }
  // Three/four-key single write (preset swatches, theme snapshot, mode +
  // tones): same one-base-text rule as writeVizOptions — two sequential
  // setText calls on the same stale base would clobber each other.
  function writeVizOptions3(key1, value1, key2, value2, key3, value3, key4, value4, key5, value5) {
    var txt = root.readGuarded()
    txt = Store.writeConfigKey(txt, "desktop", key1, value1)
    if (key2) txt = Store.writeConfigKey(txt, "desktop", key2, value2)
    if (key3) txt = Store.writeConfigKey(txt, "desktop", key3, value3)
    if (key4) txt = Store.writeConfigKey(txt, "desktop", key4, value4)
    if (key5) txt = Store.writeConfigKey(txt, "desktop", key5, value5)
    root.noteWrite(txt)
    root.flushSettings()
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    // Option 1: the mini stays in the bar while a desktop window is open,
    // but renders a paused floor (no animation, bars at bottom) instead
    // of hiding — settings stay one click away, no round-trip.
    bar: root.bar
    tooltipText: {
      var viz = root.config.visual === "Bars" ? "Spectrum" : root.config.visual
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
      color: root.config.visual === "Siri" ? "#000000" : root.config.spikes === true ? "transparent" : Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.82)
      // Spikes run borderless — the dense spectrum sits directly on the bar.
      border.width: root.config.spikes === true ? 0 : 1
      border.color: Qt.rgba(0.20, 0.20, 0.25, 0.50)

      // One shared renderer everywhere: mini uses the same VisualCanvas
      // as preview/desktop, so spikes/splits/fire/peaks look identical.
      DotsCanvas {
        anchors.fill: parent
        anchors.margins: root.config.spikes === true ? 0 : 4
        visible: root.config.dots !== false && root.config.visual !== "Siri" && root.config.visual !== "Strings" && !root.desktopLive
      }
      VisualCanvas {
        anchors.fill: parent
        anchors.margins: root.config.spikes === true ? 0 : (root.config.visual === "Siri" || root.config.visual === "Strings" ? 1 : 4)
        dots: false   // static underlay above (per-frame dots = 34K rects)
        bands: root.desktopLive ? [] : root.spectrumBands
        silent: root.desktopLive ? true : root.spectrumSilent
        visual: root.config.visual || "Bars"
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
        scopeLineWidth: root.config.scopeThickness ?? 2
        // Bar color: custom From→To wins; otherwise LIVE theme accent
        // (Theme mode always follows the Omarchy theme — no stale snapshot).
        artworkColors: root.config.artworkColors === true
        artworkPalette: root.artworkPalette
        barColorCustom: root.config.barColorCustom === true
        barColorFrom: root.config.barColorFrom || "#e68e0d"
        barColorTo: root.config.barColorTo || "#f59e0b"
        barColorMiddle: root.config.barColorMiddle || "#a855f7"
        barColorMiddleEnabled: root.config.barColorMiddleEnabled === true
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
    function selectVisual(mode: string): bool {
      if (["Bars", "Oscilloscope", "Waves", "Strings", "Siri"].indexOf(mode) < 0) return false
      root.writeVizOptions("visual", mode === "Oscilloscope" ? "Waves" : mode, "scope", mode === "Waves" || mode === "Oscilloscope")
      return true
    }
    function setEnabled(enabled: bool) { root.writeEnabled(enabled) }
    function setColorMode(mode: string): bool { return root.setColorMode(mode) }
    function setFlame(enabled: bool) { root.writeVizOption("fire", enabled) }
    function status(): string {
      return JSON.stringify({visual: root.config.visual, enabled: root.vizEnabled,
        silent: root.spectrumSilent, bands: root.spectrumBands.length, preview: root.opened,
        waveSamples: root.spectrumWave.length, engineRunning: spectrumProc.running, restarting: root._restarting})
    }
  }
}
