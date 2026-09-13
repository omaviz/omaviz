import QtQuick

// GPU spectrum renderer: same prop surface + pixels as VisualCanvas,
// raster done in gpu.frag. CPU does only band mapping, Winamp peak
// physics and a 512x3 control texture per frame (~1.5K texels).
// Emits gpuFailed() if the GL pipeline breaks — the host swaps back
// to VisualCanvas (fallback when no GPU is available).
Item {
  id: root
  property var bands: []
  property bool silent: false
  property string visual: "Bars"
  property bool colorSync: false
  property int barCount: 0
  property int gapPx: 1
  property int minBarHeight: 0   // accepted for surface parity (always 0)
  property bool peaks: true
  property real peakFalloff: 0.5
  property bool spikes: false
  property bool fire: false
  property bool splits: false
  property real sensitivity: 1.0
  property color themeBottom: "#e68e0d"
  property color themeTop: "#f59e0b"
  property var wave: []
  property real scopeLineWidth: 2
  property bool mono: false
  property bool monoLight: false
  property bool artMode: false
  property bool dots: false   // static DotsCanvas underlay owns the grid
  property bool reflect: false
  property int spikeBars: 0

  signal gpuFailed()

  property var _peakArr: []
  property var _peakSpeed: []

  // Identical mapping to VisualCanvas.displayBands (single source of
  // truth for density would be nicer; kept in sync by review).
  function displayBands() {
    var b = bands
    if (b.length === 0) return []
    var n = spikes ? (spikeBars > 0 ? spikeBars : Math.max(16, Math.floor(width / 2))) : (barCount > 0 ? barCount : b.length)
    if (n > 512) n = 512
    if (n === b.length) return b
    if (n < b.length) {
      var out = []
      for (var i = 0; i < n; i++) {
        var lo = Math.floor(i * b.length / n)
        var hi = Math.max(lo + 1, Math.floor((i + 1) * b.length / n))
        var m = 0
        for (var j = lo; j < hi; j++) {
          if (b[j] > m) m = b[j]
        }
        out.push(m)
      }
      return out
    }
    var up = []
    for (var k = 0; k < n; k++) {
      var pos = k * (b.length - 1) / (n - 1)
      var lo2 = Math.floor(pos), fr = pos - lo2
      var hi2 = Math.min(b.length - 1, lo2 + 1)
      up.push(b[lo2] * (1 - fr) + b[hi2] * fr)
    }
    return up
  }

  // Winamp peak physics, copied from VisualCanvas (hang + x1.05 accel).
  function updatePeaks(b) {
    var n = b.length
    if (_peakArr.length !== n) {
      _peakArr = []
      for (var p = 0; p < n; p++) _peakArr.push(0)
    }
    var speed0 = (1.5 + peakFalloff * 6.5) / 256
    if (_peakSpeed.length !== n) {
      _peakSpeed = []
      for (var s = 0; s < n; s++) _peakSpeed.push(speed0)
    }
    for (var i = 0; i < n; i++) {
      var v = silent ? 0 : Math.min(1, Math.max(0, b[i]) * sensitivity)
      if (v >= _peakArr[i]) { _peakArr[i] = v; _peakSpeed[i] = speed0 }
      else {
        _peakArr[i] = Math.max(0, _peakArr[i] - _peakSpeed[i])
        _peakSpeed[i] = _peakSpeed[i] * 1.05
      }
    }
  }

  function refresh() {
    if (!root.visible) return
    var b = displayBands()
    updatePeaks(b)
    // Explicit capture of the last paint, then schedule the next one.
    // update() does NOT repaint the source, so this cannot feed back.
    // NEVER call it from inside onPaint (repaint storm).
    texSrc.update()
    texCanvas.requestPaint()
  }
  onBandsChanged: root.refresh()
  onSilentChanged: root.refresh()
  onSensitivityChanged: root.refresh()
  onPeakFalloffChanged: root.refresh()
  onWaveChanged: if (visual === "Wave" || visual === "Oscilloscope") root.refresh()
  onBarCountChanged: root.refresh()
  onWidthChanged: root.refresh()
  onHeightChanged: root.refresh()
  onVisibleChanged: root.refresh()
  Component.onCompleted: {
    root.refresh()
    // No-GPU environments fail fast: fall back before first paint.
    if (fx.status === ShaderEffect.Error) root.gpuFailed()
  }

  Canvas {
    id: texCanvas
    width: 512; height: 4
    // VISIBLE source (hidden ones never paint, so explicit update()
    // captures stay empty); hideSource keeps it off the display.
    function byte2(v, scale) {
      // Exact small-int packing: round(v/scale*255), decoded by floor(*scale+.5).
      return Math.max(0, Math.min(255, Math.round(v / scale * 255)))
    }
    onPaint: {
      var ctx = getContext("2d")
      var b = root.displayBands()
      var n = Math.min(b.length, 512)
      ctx.clearRect(0, 0, 512, 4)
      for (var i = 0; i < n; i++) {
        var v = silent ? 0 : Math.min(1, Math.max(0, b[i]) * sensitivity)
        var g = Math.round(v * 255)
        ctx.fillStyle = "rgb(" + g + "," + g + "," + g + ")"
        ctx.fillRect(i, 0, 1, 1)
        var pg = Math.round(Math.min(1, Math.max(0, _peakArr[i] || 0)) * 255)
        ctx.fillStyle = "rgb(" + pg + "," + pg + "," + pg + ")"
        ctx.fillRect(i, 1, 1, 1)
      }
      var w = wave
      var wn = Math.min(w ? w.length : 0, 128)
      for (var k = 0; k < wn; k++) {
        var s = Math.min(1, Math.max(-1, w[k]))
        var wg = Math.round((s * 0.5 + 0.5) * 255)
        ctx.fillStyle = "rgb(" + wg + "," + wg + "," + wg + ")"
        ctx.fillRect(k, 2, 1, 1)
      }
      // Row 3: control cells (exact codes, see gpu.frag header).
      function cell(x, r, g, b, a) {
        if (g === undefined) g = 0
        if (b === undefined) b = 0
        if (a === undefined) a = 255
        ctx.fillStyle = "rgba(" + r + "," + g + "," + b + "," + (a / 255) + ")"
        ctx.fillRect(x, 3, 1, 1)
      }
      var vis = (visual === "Wave" || visual === "Oscilloscope") ? 1 : 0
      cell(0, vis, spikes ? 255 : 0, splits ? 255 : 0, fire ? 255 : 0)
      cell(1, dots ? 255 : 0, reflect ? 255 : 0, artMode ? 255 : 0, mono ? 255 : 0)
      cell(2, monoLight ? 255 : 0, colorSync ? 255 : 0,
           Math.round(Math.min(5, Math.max(1, scopeLineWidth)) / 5 * 255), peaks ? 255 : 0)
      cell(3, Math.round(themeBottom.r * 255), Math.round(themeBottom.g * 255), Math.round(themeBottom.b * 255))
      cell(4, Math.round(themeTop.r * 255), Math.round(themeTop.g * 255), Math.round(themeTop.b * 255))
      cell(5, texCanvas.byte2(Math.min(n, 512), 512))
      cell(6, texCanvas.byte2(Math.min(6, Math.max(0, spikes ? 0 : gapPx)), 8))
      var W = Math.min(65535, Math.max(0, Math.round(root.width)))
      var H = Math.min(65535, Math.max(0, Math.round(root.height)))
      cell(7, Math.floor(W / 256), W % 256, Math.floor(H / 256), H % 256)
    }
  }

  ShaderEffectSource {
    id: texSrc
    sourceItem: texCanvas
    // live:true re-captures on every source repaint (engine frame
    // rate). No manual update() anywhere — calling it from onPaint
    // schedules another repaint and spins the scene at full speed.
    live: true
    hideSource: true
    smooth: false   // NEAREST: control texels must stay exact
  }

  ShaderEffect {
    id: fx
    anchors.fill: parent
    property ShaderEffectSource u_tex: texSrc
    fragmentShader: Qt.resolvedUrl("gpu.qsb")
    onStatusChanged: if (status === ShaderEffect.Error) root.gpuFailed()
  }
}
