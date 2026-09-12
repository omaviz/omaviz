import QtQuick

Canvas {
  id: cv
  property var bands: []
  property bool silent: false
  property string visual: "Bars"
  property string style: "Classic"
  property bool colorSync: false
  property int barCount: 0
  property int colourScheme: 0
  property color monoColor: "#dce0eb"
  property int gapPx: 1
  property int minBarHeight: 0
  property bool peaks: true
  property real peakFalloff: 0.5
  property var _peakArr: []

  function displayBands() {
    var b = bands
    if (b.length === 0) return []
    var n = barCount > 0 ? barCount : b.length
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
      var srcIdx = Math.round(k * (b.length - 1) / (n - 1))
      up.push(b[srcIdx])
    }
    return up
  }

  onBandsChanged: requestPaint()
  onBarCountChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()

  function fillFor(h, a) {
    if (colorSync) {
      if (colourScheme === 2) {
        if (h < 0.33) return "#2a9df4"
        if (h < 0.66) return "#7b5de5"
        return "#b15bff"
      }
      if (colourScheme === 1) {
        if (h < 0.33) return "#ff5a1e"
        if (h < 0.66) return "#ff8c1a"
        return "#ffd000"
      }
      if (h < 0.33) return "#e68e0d"
      if (h < 0.66) return "#f08e0d"
      return "#f59e0b"
    }
    var bot = Qt.color("#e68e0d")
    var top = Qt.color("#ffffff")
    var r = bot.r + (top.r - bot.r) * h
    var g = bot.g + (top.g - bot.g) * h
    var b = bot.b + (top.b - bot.b) * h
    return Qt.rgba(r, g, b, 1.0)
  }

  onPaint: {
    var ctx = getContext("2d")
    ctx.clearRect(0, 0, width, height)
    var b = displayBands()
    var n = b.length
    if (!n) return
    if (visual === "Wave") { drawWave(ctx); return }

    var gap = gapPx
    var totalGap = gap * (n - 1)
    var bw = Math.max(2, (width - totalGap) / n)

    if (_peakArr.length !== n) {
      _peakArr = []
      for (var p = 0; p < n; p++) _peakArr.push(0)
    }

    var f = Math.max(0.05, 1.0 - peakFalloff * 0.12)
    for (var i = 0; i < n; i++) {
      var v = silent ? 0 : Math.min(1, Math.max(0, b[i]))
      if (v >= _peakArr[i]) { _peakArr[i] = v } else { _peakArr[i] = _peakArr[i] * f }
    }

    for (var i = 0; i < n; i++) {
      var v = silent ? 0 : Math.min(1, Math.max(0, b[i]))
      var h = v * height
      if (h > 0 && h < minBarHeight) h = minBarHeight
      var x = i * (bw + gap)
      var y = height - h
      ctx.fillStyle = fillFor(v, 0.25 + v * 0.75)
      ctx.beginPath()
      var r = Math.min(bw * 0.5, 3)
      if (ctx.roundRect) ctx.roundRect(x, y, bw, h, r); else ctx.rect(x, y, bw, h)
      ctx.fill()
    }

    if (peaks) {
      ctx.fillStyle = "#ffffff"
      for (var p = 0; p < n; p++) {
        var pv = _peakArr[p]
        if (pv < 0.02) continue
        var py = height - pv * height
        var px = p * (bw + gap)
        ctx.fillRect(px, py - 1, bw, 2)
      }
    }
  }

  function drawWave(ctx) {
    var b = displayBands()
    var n = b.length
    var mid = height * 0.5
    var step = Math.max(1, Math.floor(width / 220))
    ctx.lineWidth = 2.5
    ctx.strokeStyle = fillFor(0.8, 0.9)
    ctx.beginPath()
    for (var x = 0; x <= width; x += step) {
      var t = x / width
      var bi = Math.min(n - 1, Math.floor(t * n))
      var env = Math.min(1, b[bi]) * (0.35 + 0.65 * Math.sin(t * Math.PI))
      var y = mid - (height * 0.42) * env * Math.sin((x / width) * Math.PI * 6)
      if (x === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
    }
    ctx.stroke()
  }
}
