import QtQuick
import "Physics.js" as Physics
import "native" as Native

Item {
  id: cv
  property var bands: []
  // `silent` is now ADVISORY ONLY (drives the settle optimisation). It never
  // zeroes bars — the engine's silence flag used to hard-zero every bar on any
  // quiet passage, which is what made faint audio invisible and made bars
  // vanish instantly instead of falling.
  property bool silent: false
  property string visual: "Bars"
  // NOTE: colorSync is declared ONCE, further down with its rationale — a
  // second declaration here made the QML engine reject the whole type
  // ("Duplicate property name" -> "Type VisualCanvas unavailable"), which is
  // what silently killed the mini widget.
  property int barCount: 0
  property color monoColor: "#dce0eb"
  property int gapPx: 1
  property int barWidthExtra: 0
  property bool peaks: true
  property real peakFalloff: 0.5
  // Winamp peak caps: hold the high-water mark for this long, then fall with
  // an accelerating speed (see Physics.js).
  property real peakSustainMs: 100
  // Bar release shape: true = fixed-rate linear drop, false = exponential.
  property bool linearFall: true
  // Targets below this are treated as zero so inaudible noise does not render
  // as a permanently jittering 1px floor.
  property real noiseFloor: 0.02
  property bool spikes: false
  property bool fire: false
  property color fireColorFrom: "#be1400"
  property color fireColorTo: "#fde047"
  property bool stacks: false
  // Stack segment scale: desktop doubles block size (1 = preview/mini).
  property int stackScale: 1
  property real sensitivity: 1.0
  // Theme-anchored colors (bound from config; no hardcoded palettes).
  property color themeBottom: "#e68e0d"
  property color themeTop: "#f59e0b"
  // Bar color override (new): when barColorCustom is true the From→To pair
  // replaces the theme gradient on every surface (mini unless mono,
  // preview, desktop, wave). Off = theme dominant colors (default).
  property bool artworkColors: false
  property var artworkPalette: []
  readonly property bool artMode: artworkColors && visual === "Bars"
  readonly property bool artReady: artMode && artworkPalette.length >= 3
  readonly property bool customMode: !artMode && barColorCustom
  property bool barColorCustom: false
  property color barColorFrom: "#e68e0d"
  property color barColorMiddle: "#a855f7"
  property bool barColorMiddleEnabled: false
  property color barColorTo: "#f59e0b"
  // Bar gradient direction: "vertical" (bottom -> top, default) or
  // "horizontal" (left -> right across the whole bar field).
  property string gradientDir: "vertical"
  // Color sync: ON by default so theme gradient (themeBottom→themeTop) works.
  // When OFF, gradient goes themeBottom→white (legacy behavior).
  property bool colorSync: true
  // Oscilloscope feed: 128-point time-domain samples (-1..1, newest last).
  property var wave: []
  property real scopeLineWidth: 2
  // B&W mode (mini option): solid black on light themes, white on dark.
  // Takes precedence over Fire — an explicit monochrome choice.
  property bool mono: false
  property bool monoLight: false
  // Glow wash bound from the Artwork-backdrop toggle (preview/desktop).
  property bool wash: false
  // Winamp skin dressing: dotted backdrop (on) and floor reflection (off).
  property bool dots: false   // static DotsCanvas underlay owns the grid
  property bool reflect: false
  // Spike density cap: 0 = auto (~2px per bar across full width).
  // Mini passes 32 to keep its density down.
  property int spikeBars: 0
  property var _peakArr: []
  property var _peakSpeed: []
  property var _peakHold: []
  // Rendered bar heights (release envelope) — what actually gets painted.
  property var _barArr: []
  // Scratch target buffer (raw bands * sensitivity) handed to Physics.step.
  property var _targets: []

  function displayBands() {
    var b = bands
    if (!b || b.length === 0) return []
    // Spikes mode: dense gapless spectrum (~2px per bar, like the
    // Winamp thin-bar visualizer) instead of the barCount mapping —
    // unless spikeBars caps it (mini holds 32).
    var n = spikes ? (spikeBars > 0 ? spikeBars : Math.max(16, Math.floor(width / 2))) : (barCount > 0 ? barCount : b.length)
    if (n === b.length) return b
    if (n < b.length) {
      var out = _bandBuf.length === n ? _bandBuf : (_bandBuf = new Array(n))
      for (var i = 0; i < n; i++) {
        var lo = Math.floor(i * b.length / n)
        var hi = Math.max(lo + 1, Math.floor((i + 1) * b.length / n))
        var m = 0
        for (var j = lo; j < hi; j++) {
          if (b[j] > m) m = b[j]
        }
        out[i] = m
      }
      return out
    }
    var up = _bandUp.length === n ? _bandUp : (_bandUp = new Array(n))
    // Linear interpolation (not nearest-neighbor): duplicating source bands
    // makes groups of bars move in lockstep ("5 bars in sync"); blending
    // between neighbors keeps dense modes looking like a real spectrum.
    for (var k = 0; k < n; k++) {
      var pos = k * (b.length - 1) / (n - 1)
      var lo = Math.floor(pos), fr = pos - lo
      var hi = Math.min(b.length - 1, lo + 1)
      up[k] = b[lo] * (1 - fr) + b[hi] * fr
    }
    return up
  }

  // All surfaces use this clock and this native geometry backend.
  // dataFps is retained for API compatibility; physics always uses 60 Hz steps.
  property real dataFps: 60
  property var _bandBuf: []
  property var _bandUp: []
  property bool _awake: true
  property bool _waveDirty: true
  property real _accumulator: 0
  property real _phase: 0
  property real _waveTail: 0
  property var _lastWave: []
  readonly property bool _scopeMode: visual === "Wave" || visual === "Oscilloscope" || visual === "Waves" || visual === "Strings" || visual === "Siri"

  function wake() {
    if (visible) _awake = true
  }
  function advance(dt) {
    var b = displayBands(), n = b.length
    _barArr = Physics.ensure(_barArr, n, 0)
    _peakArr = Physics.ensure(_peakArr, n, 0)
    _peakHold = Physics.ensure(_peakHold, n, 0)
    _peakSpeed = Physics.ensure(_peakSpeed, n, Physics.peakSpeed0(peakFalloff))
    _targets = Physics.ensure(_targets, n, 0)
    for (var i = 0; i < n; ++i) {
      var target = Physics.clamp01(b[i] * sensitivity)
      _targets[i] = target < noiseFloor ? 0 : target
    }
    Physics.step(_barArr, _peakArr, _peakHold, _peakSpeed, _targets, dt, {
      linearFall: linearFall, peakFalloff: peakFalloff,
      peakSustainMs: peakSustainMs, noiseFloor: noiseFloor
    })
  }
  onBandsChanged: {
    if (_scopeMode) return
    if (!silent || !Physics.settled(_barArr, _peakArr, _targets, 0.002)) { wake(); return }
    var mapped = displayBands()
    if (mapped.length !== _targets.length) { wake(); return }
    for (var i = 0; i < mapped.length; ++i) {
      var target = Physics.clamp01(mapped[i] * sensitivity)
      if (target < noiseFloor) target = 0
      if (Math.abs(target - _targets[i]) > 0.00001) { wake(); return }
    }
  }
  onWaveChanged: {
    if (!_scopeMode) return
    var changed = wave.length !== _lastWave.length
    for (var i = 0; !changed && i < wave.length; ++i) changed = wave[i] !== _lastWave[i]
    if (changed) { _lastWave = wave; _waveDirty = true; wake() }
  }
  onVisibleChanged: { if (visible) { _accumulator = 0; wake() } }
  onVisualChanged: { _waveDirty = true; wake() }
  onWidthChanged: wake()
  onBarCountChanged: wake()
  onSpikesChanged: wake()
  onSpikeBarsChanged: wake()
  onSensitivityChanged: wake()
  onPeakFalloffChanged: wake()
  onPeakSustainMsChanged: wake()
  onLinearFallChanged: wake()
  onNoiseFloorChanged: wake()

  FrameAnimation {
    running: cv.visible && cv._awake
    onTriggered: {
      // Bound catch-up after suspension, and preserve original x1.05 peak
      // acceleration by stepping at exactly 1/60 s independently of arrivals.
      cv._accumulator += Math.min(frameTime * 1000, 100)
      if (cv._accumulator + 0.01 < 1000 / 60) return
      while (cv._accumulator + 0.01 >= 1000 / 60) {
        if (!cv._scopeMode) cv.advance(1000 / 60)
        cv._phase += 1 / 60
        cv._waveTail = cv.silent ? Math.max(0, cv._waveTail - 1 / 60) : 0.8
        cv._accumulator -= 1000 / 60
      }
      mesh.submit(cv.visual === "Strings" ? cv.bands : cv._barArr,
                  cv._peakArr, cv.wave, cv._phase)
      var flowing = !cv.silent || ((cv.visual === "Siri" || cv.visual === "Strings") && cv._waveTail > 0)
      cv._awake = flowing || (!cv._scopeMode && !Physics.settled(cv._barArr, cv._peakArr, cv._targets, 0.002))
      cv._waveDirty = false
    }
  }

  Native.VisualGeometry {
    id: mesh
    anchors.fill: parent
    style: ({
      mode: cv.visual, bottom: Qt.darker(cv.artReady ? cv.artworkPalette[0] : cv.customMode ? cv.barColorFrom : cv.themeBottom, 1.25),
      top: Qt.lighter(cv.artReady ? cv.artworkPalette[2] : cv.customMode ? cv.barColorTo : (cv.colorSync ? cv.themeTop : "#ffffff"), 1.2),
      middle: cv.artReady ? cv.artworkPalette[1] : cv.barColorMiddle, middleEnabled: cv.artReady || (cv.customMode && cv.barColorMiddleEnabled),
      custom: cv.customMode || cv.artReady, mono: cv.mono, monoLight: cv.monoLight, fire: !cv.artMode && cv.fire && cv.visual !== "Siri" && cv.visual !== "Strings",
      fireBottom: cv.fireColorFrom, fireTop: cv.fireColorTo,
      horizontal: cv.gradientDir === "horizontal", gap: cv.gapPx,
      extraWidth: cv.barWidthExtra, peaks: cv.peaks, reflect: cv.reflect,
      spikes: cv.spikes, stacks: cv.stacks, stackScale: cv.stackScale,
      wash: cv.wash, lineWidth: cv.scopeLineWidth, gain: cv.sensitivity
    })
  }
}
