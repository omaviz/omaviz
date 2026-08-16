import QtQuick

// Shared visualization renderer (self-contained QML, no WGSL, no shell-only
// modules so it loads both inside the shell and as a standalone Loader).
// `visual` selects the base shape:
//   "Bars" — vertical spectrum bars (default bar spectrograph)
//   "Wave" — smooth mirrored sine ribbon (string-like)
// `style` ("Classic" | "Fire") layers a winamp-style flame over the Bars
// visual. Fire is a STYLE of the bar visual, not a separate visualization.
// `colorSync` = false renders monochrome (mini/panel look); true renders
// colored (desktop showcase). Driven live by `bands`/`silent`.

Canvas {
  id: cv
  property var bands: []
  property bool silent: false
  property string visual: "Bars"
  property string style: "Classic"
  property bool colorSync: false
  property int barCount: 0   // 0 = use all bands; else downsample to this many bars
  property int colourScheme: 0  // 0=theme(mono), 1=warm, 2=cool
  property color monoColor: "#dce0eb"

  // Downsample the raw spectrum to `barCount` display bars (if requested).
  function displayBands() {
    var b = bands
    var n = barCount > 0 ? barCount : b.length
    if (n === b.length || b.length === 0) return b
    var out = []
    for (var i = 0; i < n; i++) {
      var lo = Math.floor(i * b.length / n)
      var hi = Math.max(lo + 1, Math.floor((i + 1) * b.length / n))
      var m = 0
      for (var j = lo; j < hi; j++) m += b[j]
      out.push(m / (hi - lo))
    }
    return out
  }

  onBandsChanged: requestPaint()
  onVisualChanged: requestPaint()
  onStyleChanged: requestPaint()
  onSilentChanged: requestPaint()
  onColorSyncChanged: requestPaint()
  onBarCountChanged: requestPaint()
  onColourSchemeChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()

  function cssMonoTint(a) { return "rgba(220,224,235," + a.toFixed(3) + ")" }
  function cssColorFor(h) {
    if (colourScheme === 2) { // cool
      if (h < 0.33) return "#2a9df4"
      if (h < 0.66) return "#7b5de5"
      return "#b15bff"
    }
    if (colourScheme === 1) { // warm
      if (h < 0.33) return "#ff5a1e"
      if (h < 0.66) return "#ff8c1a"
      return "#ffd000"
    }
    if (h < 0.33) return "#2a9df4"
    if (h < 0.66) return "#9b5de5"
    return "#f15bb5"
  }
  function fillFor(h, a) { return colorSync ? cssColorFor(h) : cssMonoTint(a) }
  function isFire() { return style === "Fire" && visual === "Bars" }

  onPaint: {
    var ctx = getContext("2d")
    ctx.clearRect(0, 0, width, height)
    var n = displayBands().length
    if (!n) return
    if (visual === "Wave") drawWave(ctx)
    else if (isFire()) drawFireBars(ctx)
    else drawBars(ctx)
  }

  // ---- Classic Bars ----
  function drawBars(ctx) {
    var b = displayBands()
    var n = b.length
    var gap = width * 0.012
    var slot = width / n
    var bw = Math.max(1, slot - gap)
    for (var i = 0; i < n; i++) {
      var v = Math.min(1, Math.max(0, b[i]))
      if (silent) v = 0
      var h = v * (height * 0.92)
      var x = i * slot + gap / 2
      var y = height - h
      ctx.fillStyle = fillFor(v, 0.25 + v * 0.75)
      ctx.beginPath()
      var r = Math.min(bw * 0.5, 3)
      if (ctx.roundRect) ctx.roundRect(x, y, bw, h, r); else ctx.rect(x, y, bw, h)
      ctx.fill()
    }
  }

  // ---- Bars styled as a winamp-style flame ----
  function drawFireBars(ctx) {
    var b = displayBands()
    var n = b.length
    var gap = width * 0.018
    var slot = width / n
    var bw = Math.max(1.5, slot - gap)
    var energy = 0
    for (var e = 0; e < n; e++) energy += b[e]
    energy = energy / n
    var bg = ctx.createLinearGradient(0, height, 0, 0)
    bg.addColorStop(0, "rgba(255,90,20," + (0.10 + energy * 0.25).toFixed(3) + ")")
    bg.addColorStop(1, "rgba(60,0,0,0)")
    ctx.fillStyle = bg
    ctx.fillRect(0, 0, width, height)

    ctx.beginPath()
    ctx.moveTo(0, height)
    for (var i = 0; i < n; i++) {
      var v = silent ? 0 : Math.min(1, Math.max(0, b[i]))
      var h = v * (height * 0.96)
      var x = i * slot
      var y = height - h
      var flick = (i % 2 ? 1 : -1) * (3 + v * 6)
      ctx.lineTo(x + bw * 0.5, y + flick)
      ctx.lineTo(x + slot, height - h * 0.82)
    }
    ctx.lineTo(width, height)
    ctx.closePath()
    var fg = ctx.createLinearGradient(0, height, 0, 0)
    if (colorSync) {
      fg.addColorStop(0.0, "#ff2d00")
      fg.addColorStop(0.45, "#ff7b00")
      fg.addColorStop(0.8, "#ffd000")
      fg.addColorStop(1.0, "#fff27a")
    } else {
      fg.addColorStop(0.0, "rgba(255,180,120,0.55)")
      fg.addColorStop(1.0, "rgba(255,255,255,0.95)")
    }
    ctx.fillStyle = fg
    ctx.fill()

    for (var p = 0; p < n; p++) {
      var pv = silent ? 0 : Math.min(1, Math.max(0, b[p]))
      if (pv < 0.04) continue
      var px = p * slot + slot * 0.5
      var py = height - pv * (height * 0.96)
      ctx.fillStyle = colorSync ? "#fff7c0" : "rgba(255,255,255,0.9)"
      ctx.beginPath()
      ctx.arc(px, py, Math.max(1, bw * 0.32), 0, Math.PI * 2)
      ctx.fill()
    }
  }

  // ---- Wave (mirrored sine ribbon, string-like) ----
  function drawWave(ctx) {
    var b = displayBands()
    var n = b.length
    var mid = height * 0.5
    var step = Math.max(1, Math.floor(width / 220))
    function envAt(x) {
      var t = x / width
      var bi = Math.min(n - 1, Math.floor(t * n))
      return Math.min(1, b[bi]) * (0.35 + 0.65 * Math.sin(t * Math.PI))
    }
    ctx.lineWidth = 2.5
    ctx.strokeStyle = fillFor(0.8, 0.9)
    ctx.beginPath()
    for (var x = 0; x <= width; x += step) {
      var env = envAt(x)
      var y = mid - (height * 0.42) * env * Math.sin((x / width) * Math.PI * 6)
      if (x === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
    }
    ctx.stroke()
    ctx.lineTo(width, mid); ctx.lineTo(0, mid); ctx.closePath()
    ctx.fillStyle = fillFor(0.6, 0.12)
    ctx.fill()
  }
}
