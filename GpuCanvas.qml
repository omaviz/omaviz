import QtQuick

// GPU spectrum renderer with full feature parity to VisualCanvas.qml
// Rasterization done via shaders for performance — CPU only handles band mapping,
// peak physics, and control state. Data texture is 512x4 (NEAREST): row0=bands,
// row1=peak-hold, row2=wave, row3=control cells. All scalars ride as exact texels.
// Emits gpuFailed() if the GL pipeline breaks — the host swaps back to VisualCanvas.
Item {
  id: root
  property var bands: []
  property bool silent: false
  property string visual: "Bars"
  property bool colorSync: false
  property int barCount: 0
  property int gapPx: 1
  property int minBarHeight: 1
  property bool peaks: true
  property real peakFalloff: 0.5
  property bool spikes: false
  property bool fire: false
  property bool stacks: false
  property int stackScale: 1
  property bool barColorCustom: false
  property color barColorFrom: "#e68e0d"
  property color barColorTo: "#f59e0b"
  property real sensitivity: 1.0
  property color themeBottom: "#e68e0d"
  property color themeTop: "#f59e0b"
  property var wave: []
  property real scopeLineWidth: 2
  property bool mono: false
  property bool monoLight: false
  property bool artMode: false
  property bool dots: false
  property bool reflect: false
  property int spikeBars: 0
  property var _peakArr: []
  property var _peakSpeed: []

  signal gpuFailed()

  // snapshot of displayBands() for the texture upload — mirrors the bars
  // the GLSL shader reads, so peak/reflect logic stays consistent.
  property var snapBands: []

  function refresh() {
    if (!root.visible) return
    var b = displayBands()
    updatePeaks(b)
    root.snapBands = b
    texCanvas.requestPaint()
  }

  function displayBands() {
    var b = bands
    if (!b || b.length === 0) return []
    var n = spikes ? (spikeBars > 0 ? spikeBars : Math.max(16, Math.floor(width / 2))) : (barCount > 0 ? barCount : b.length)
    if (n > 512) n = 512
    if (n === b.length) return b
    if (n < b.length) {
      var out = []
      for (var i = 0; i < n; i++) {
        var lo = Math.floor(i * b.length / n)
        var hi = Math.max(lo + 1, Math.floor((i + 1) * b.length / n))
        var m = 0
        for (var j = lo; j < hi; j++) if (b[j] > m) m = b[j]
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

  // Fire color at height fraction t (0 = base, 1 = tip): deep red base,
  // orange mid, white-hot tip — classic Winamp flame on near-black.
  function fireColorAt(t) {
    t = Math.min(1, Math.max(0, t))
    var r, g, b
    if (t < 0.25) {
      var k = t / 0.25
      r = Math.round(190 + k * 65); g = Math.round(20 + k * 120); b = Math.round(0 + k * 10)
    } else {
      var k2 = (t - 0.25) / 0.75
      r = 255; g = Math.round(140 + k2 * 110); b = Math.round(10 + k2 * 190)
    }
    return "rgba(" + r + "," + g + "," + b + ",1)"
  }

  // Theme-anchored fill color for solid bars (matches VisualCanvas.fillFor)
  function fillFor(h, a) {
    if (artMode) return "#ffffff"
    if (mono) return monoLight ? "#000000" : "#ffffff"
    if (fire) {
      // Winamp flame, kept luminous at low levels so quiet bars stay
      // visible on dark containers (dark reds vanish; orange does not).
      return "rgba(255," + Math.round(140 + h * 115) + "," + Math.round(60 + h * 40) + ",1)"
    }
    // Theme-anchored: colorSync blends bottom→top theme colors,
    // otherwise bottom rises toward white-hot with bar height.
    var bot = themeBottom, top = colorSync ? themeTop : Qt.color("#ffffff")
    var r = Math.round(bot.r + (top.r - bot.r) * h)
    var g = Math.round(bot.g + (top.g - bot.g) * h)
    var b = Math.round(bot.b + (top.b - bot.b) * h)
    return Qt.rgba(r, g, b, 1.0)
  }

  // Theme-anchored wash color (matches VisualCanvas.fillWash)
  function fillWash(h) {
    var bot = themeBottom, top = colorSync ? themeTop : Qt.color("#ffffff")
    var r = Math.round(bot.r + (top.r - bot.r) * h)
    var g = Math.round(bot.g + (top.g - bot.g) * h)
    var b = Math.round(bot.b + (top.b - bot.b) * h)
    return "rgba(" + r + "," + g + "," + b + ",0.10)"
  }

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

  onBandsChanged: root.refresh()
  onSilentChanged: root.refresh()
  onWaveChanged: if (visual === "Wave" || visual === "Oscilloscope") root.refresh()
  onBarCountChanged: root.refresh()
  onWidthChanged: root.refresh()
  onHeightChanged: root.refresh()
  onVisibleChanged: root.refresh()
  Component.onCompleted: root.refresh()

  // Data texture: 512 wide, 4 high. Uploaded from CPU each frame.
  // Row 0: spectrum bands (512 values as texel luminance)
  // Row 1: peak-hold magnitudes (512 values as texel luminance)
  // Row 2: 128-point time-domain wave sample (-1..1)
  // Row 3: control cells packed into RGBA:
  //   r: visual (0=Bars, 1=Wave, 2=Oscilloscope, 3=spikes),
  //   g: spikes/ splits/ fire/ dots/ reflect/ mono/ monoLight/ artMode as flags
  //   b: themeBottom.r*255, themeTop.r*255 (or combined)
  //   a: barCount, gapPx, width hi+lo bytes

  Canvas {
    id: texCanvas
    width: 512; height: 4
    visible: true
    onPaint: {
      var ctx = getContext("2d")
      var b = root.snapBands
      var n = Math.min(b.length, 512)
      ctx.clearRect(0, 0, 512, 4)
      // Row 0: spectrum magnitudes
      for (var i = 0; i < n; i++) {
        var v = silent ? 0 : Math.min(1, Math.max(0, b[i]) * root.sensitivity)
        var g = Math.round(v * 255)
        ctx.fillStyle = "rgb(" + g + "," + g + "," + g + ")"
        ctx.fillRect(i, 0, 1, 1)
      }
      // Row 1: peak-hold magnitudes (JS-maintained)
      for (var j = 0; j < n; j++) {
        var pg = Math.round(Math.min(1, Math.max(0, root._peakArr[j] || 0)) * 255)
        ctx.fillStyle = "rgb(" + pg + "," + pg + "," + pg + ")"
        ctx.fillRect(j, 1, 1, 1)
      }
      // Row 2: wave (128-point time-domain)
      var w = root.wave
      var wn = Math.min(w ? w.length : 0, 128)
      for (var k = 0; k < wn; k++) {
        var s = Math.min(1, Math.max(-1, w[k]))
        var wg = Math.round((s * 0.5 + 0.5) * 255)
        ctx.fillStyle = "rgb(" + wg + "," + wg + "," + wg + ")"
        ctx.fillRect(k, 2, 1, 1)
      }
      // Row 3: control cells (exact codes, see GLSL shader header)
      // OPAQUE — alpha is never data; transparent texels premultiply to 0
      function cell(x, r, g, b) {
        if (g === undefined) g = 0
        if (b === undefined) b = 0
        ctx.fillStyle = "rgb(" + r + "," + g + "," + b + ")"
        ctx.fillRect(x, 3, 1, 1)
      }
      var vis = (root.visual === "Wave" || root.visual === "Oscilloscope") ? 255 : 0
      cell(0, vis, root.spikes ? 255 : 0, root.stacks ? 255 : 0)
      cell(1, root.dots ? 255 : 0, root.reflect ? 255 : 0, root.artMode ? 255 : 0)
      cell(2, mono ? 255 : 0, peaks ? 255 : 0, fire ? 255 : 0)
      cell(3, monoLight ? 255 : 0, colorSync ? 255 : 0,
           Math.round(Math.min(5, Math.max(1, root.scopeLineWidth)) / 5 * 255))
      cell(4, Math.round(root.themeBottom.r * 255), Math.round(root.themeBottom.g * 255), Math.round(root.themeBottom.b * 255))
      cell(5, Math.round(root.themeTop.r * 255), Math.round(root.themeTop.g * 255), Math.round(root.themeTop.b * 255))
      cell(6, Math.min(n, 512))
      cell(7, Math.min(6, Math.max(0, root.spikes ? 0 : root.gapPx)))
      var W = Math.min(65535, Math.max(0, Math.round(root.width)))
      var H = Math.min(65535, Math.max(0, Math.round(root.height)))
      cell(8, Math.floor(W / 256), W % 256)
      cell(9, Math.floor(H / 256), H % 256)
      // Custom swatch + stack scale + sensitivity (shader mirrors the
      // Canvas ramp: base ignites red under fire, tip lands on To/accent).
      cell(10, root.barColorCustom ? 255 : 0,
           Math.round(root.barColorFrom.r * 255), Math.round(root.barColorFrom.g * 255))
      cell(11, Math.round(root.barColorFrom.b * 255),
           Math.round(root.barColorTo.r * 255), Math.round(root.barColorTo.g * 255))
      cell(12, Math.round(root.barColorTo.b * 255),
           Math.max(1, Math.round(root.stackScale)),
           Math.min(255, Math.max(0, Math.round(root.sensitivity * 100))))
    }
  }

  ShaderEffectSource {
    id: texSrc
    sourceItem: texCanvas
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