import QtQuick

Canvas {
  id: cv
  property var bands: []
  property bool silent: false
  property string visual: "Bars"
  property bool colorSync: false
  property int barCount: 0
  property color monoColor: "#dce0eb"
  property int gapPx: 1
  property int minBarHeight: 0
  property bool peaks: true
  property real peakFalloff: 0.5
  property bool spikes: false
  property bool fire: false
  property bool splits: false
  property real sensitivity: 1.0
  // Theme-anchored colors (bound from config; no hardcoded palettes).
  property color themeBottom: "#e68e0d"
  property color themeTop: "#f59e0b"
  // Oscilloscope feed: 128-point time-domain samples (-1..1, newest last).
  property var wave: []
  property real scopeLineWidth: 2
  // B&W mode (mini option): solid black on light themes, white on dark.
  // Takes precedence over Fire — an explicit monochrome choice.
  property bool mono: false
  property bool monoLight: false
  property bool immersive: false
  // Immersive mode (Plexamp-style): reactive glow wash behind quiet
  // white bars. Foreground is always white; art (desktop-only Image
  // layer) sits behind the wash when available.
  // Winamp skin dressing: dotted backdrop (on) and floor reflection (off).
  property bool dots: true
  property bool reflect: false
  // Spike density cap: 0 = auto (~2px per bar across full width).
  // Mini passes 32 to keep its density down.
  property int spikeBars: 0
  property var _peakArr: []
  property var _peakSpeed: []

  function displayBands() {
    var b = bands
    if (b.length === 0) return []
    // Spikes mode: dense gapless spectrum (~2px per bar, like the
    // Winamp thin-bar visualizer) instead of the barCount mapping —
    // unless spikeBars caps it (mini holds 32).
    var n = spikes ? (spikeBars > 0 ? spikeBars : Math.max(16, Math.floor(width / 2))) : (barCount > 0 ? barCount : b.length)
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
    // Linear interpolation (not nearest-neighbor): duplicating source bands
    // makes groups of bars move in lockstep ("5 bars in sync"); blending
    // between neighbors keeps dense modes looking like a real spectrum.
    for (var k = 0; k < n; k++) {
      var pos = k * (b.length - 1) / (n - 1)
      var lo = Math.floor(pos), fr = pos - lo
      var hi = Math.min(b.length - 1, lo + 1)
      up.push(b[lo] * (1 - fr) + b[hi] * fr)
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

  onBandsChanged: requestPaint()
  onBarCountChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()
  onWaveChanged: if (visual === "Wave" || visual === "Oscilloscope") requestPaint()
  onDotsChanged: requestPaint()
  onReflectChanged: requestPaint()
  onSpikesChanged: requestPaint()
  onFireChanged: requestPaint()
  onSplitsChanged: requestPaint()
  onSensitivityChanged: requestPaint()
  onThemeBottomChanged: requestPaint()
  onThemeTopChanged: requestPaint()
  onVisualChanged: requestPaint()
  onPeaksChanged: requestPaint()
  onPeakFalloffChanged: requestPaint()
  onScopeLineWidthChanged: requestPaint()
  onMonoChanged: requestPaint()
  onMonoLightChanged: requestPaint()
  onImmersiveChanged: requestPaint()

  function fillFor(h, a) {
    if (immersive) return "#ffffff"
    if (mono) return monoLight ? "#000000" : "#ffffff"
    if (fire) {
      // Winamp flame, kept luminous at low levels so quiet bars stay
      // visible on dark containers (dark reds vanish; orange does not).
      return "rgba(255," + Math.round(140 + h * 115) + "," + Math.round(60 + h * 40) + ",1)"
    }
    // Theme-anchored: colorSync blends bottom→top theme colors,
    // otherwise bottom rises toward white-hot with bar height.
    var bot = themeBottom, top = colorSync ? themeTop : Qt.color("#ffffff")
    var r = bot.r + (top.r - bot.r) * h
    var g = bot.g + (top.g - bot.g) * h
    var b = bot.b + (top.b - bot.b) * h
    return Qt.rgba(r, g, b, 1.0)
  }

  function fillWash(h) {
    var bot = themeBottom, top = colorSync ? themeTop : Qt.color("#ffffff")
    var r = Math.round(bot.r + (top.r - bot.r) * h)
    var g = Math.round(bot.g + (top.g - bot.g) * h)
    var b = Math.round(bot.b + (top.b - bot.b) * h)
    return "rgba(" + r + "," + g + "," + b + ",0.16)"
  }

  onPaint: {
    var ctx = getContext("2d")
    ctx.clearRect(0, 0, width, height)
    if (dots) drawDots(ctx)
    var b = displayBands()
    var n = b.length
    if (!n) return
    if (visual === "Wave" || visual === "Oscilloscope") { drawWave(ctx); return }
    // Reflection zone: bars live in the top ~2/3 anchored at baseY, the
    // mirror fades below. Otherwise the full height is the bar area.
    var areaH = reflect ? height * 0.62 : height
    var baseY = reflect ? height * 0.68 : height
    if (immersive) {
      // Reactive glow wash: wide soft color fields at low alpha behind
      // the white bars. Follows Fire when on, theme gradient otherwise.
      for (var g = 0; g < n; g++) {
        var gv = silent ? 0 : Math.min(1, Math.max(0, b[g]) * sensitivity)
        var gw = width / n
        var gx = g * gw - gw
        var gh = Math.max(2, gv * height)
        if (fire) ctx.fillStyle = "rgba(255," + Math.round(120 + gv * 120) + ",60,0.16)"
        else ctx.fillStyle = fillWash(gv)
        ctx.fillRect(gx, height - gh, gw * 3, gh)
      }
    }

    var gap = spikes ? 0 : gapPx
    var totalGap = gap * (n - 1)
    var bw = spikes ? Math.max(1, width / n) : Math.max(2, (width - totalGap) / n)
    // Spike overlap: fractional widths leave 1px container seams between
    // bars — draw each spike half a pixel wider to seal them.
    var spikeOverlap = spikes ? 0.5 : 0

    if (_peakArr.length !== n) {
      _peakArr = []
      for (var p = 0; p < n; p++) _peakArr.push(0)
    }

    // Winamp peak physics: caught peaks reset a slow drop speed that
    // accelerates ×1.05/frame — hang, then snap down (not linear decay).
    // falloff maps to initial drop speed (~1.5/256 → ~8/256 per frame).
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

    for (var i = 0; i < n; i++) {
      var v = silent ? 0 : Math.min(1, Math.max(0, b[i]) * sensitivity)
      var h = v * areaH
      if (h > 0 && h < minBarHeight) h = minBarHeight
      var x = i * (bw + gap)
      var y = baseY - h
      if (h <= 0) continue
      if (splits) {
        // Winamp segments: 3px blocks with 1px gaps, stacked from the base.
        // Each block samples the fire ramp (or flat fill) at its own height
        // so the red-to-hot gradient climbs the bar like a real flame.
        var segH = 3, segGap = 1, sy = baseY
        while (sy > y) {
          var sh = Math.min(segH, sy - y)
          var tMid = 1 - (sy - sh / 2 - (baseY - areaH)) / areaH
          ctx.fillStyle = fire ? fireColorAt(tMid) : fillFor(v, 0.25 + v * 0.75)
          ctx.fillRect(x, sy - sh, bw + spikeOverlap, sh)
          sy -= segH + segGap
        }
        if (spikes) {
          ctx.beginPath()
          ctx.moveTo(x, y)
          ctx.lineTo(x + bw + spikeOverlap, y)
          ctx.lineTo(x + bw / 2, Math.max(0, y - Math.min(bw, 5)))
          ctx.closePath()
          ctx.fill()
        }
      } else if (spikes) {
        // Pointed tip: sharp triangle apex over a square body.
        // Fire: vertical red-to-hot gradient along the bar area.
        if (mono || immersive) {
          if (immersive) ctx.fillStyle = "#ffffff";
          else ctx.fillStyle = monoLight ? "#000000" : "#ffffff";
        }
        if (!mono && !immersive && fire) {
          var g1 = ctx.createLinearGradient(0, baseY, 0, baseY - areaH)
          g1.addColorStop(0, fireColorAt(0))
          g1.addColorStop(0.25, fireColorAt(0.25))
          g1.addColorStop(1, fireColorAt(1))
          ctx.fillStyle = g1
        } else {
          ctx.fillStyle = fillFor(v, 0.25 + v * 0.75)
        }
        var tipH = Math.min(Math.max(bw, 3), 7)
        if (h > tipH + 1) {
          ctx.fillRect(x, y + tipH, bw + spikeOverlap, h - tipH)
          ctx.beginPath()
          ctx.moveTo(x, y + tipH)
          ctx.lineTo(x + bw + spikeOverlap, y + tipH)
          ctx.lineTo(x + bw / 2, y)
          ctx.closePath()
          ctx.fill()
        } else {
          ctx.beginPath()
          ctx.moveTo(x, y + h)
          ctx.lineTo(x + bw + spikeOverlap, y + h)
          ctx.lineTo(x + bw / 2, y)
          ctx.closePath()
          ctx.fill()
        }
      } else {
        if (mono || immersive) {
          if (immersive) ctx.fillStyle = "#ffffff";
          else ctx.fillStyle = monoLight ? "#000000" : "#ffffff";
        }
        else if (!immersive && fire) {
          var g2 = ctx.createLinearGradient(0, baseY, 0, baseY - areaH)
          g2.addColorStop(0, fireColorAt(0))
          g2.addColorStop(0.25, fireColorAt(0.25))
          g2.addColorStop(1, fireColorAt(1))
          ctx.fillStyle = g2
        } else {
          ctx.fillStyle = fillFor(v, 0.25 + v * 0.75)
        }
        ctx.beginPath()
        var r = Math.min(bw * 0.5, 3)
        if (ctx.roundRect) ctx.roundRect(x, y, bw, h, r); else ctx.rect(x, y, bw, h)
        ctx.fill()
      }
    }

    if (peaks) {
      // Thin-spike caps: 1px hot ticks (a 2px block would swallow a 2px bar).
      // Mono: caps match the bars (ticks sit on the background above them).
      if (immersive) ctx.fillStyle = "#ffffff";
      else if (mono) ctx.fillStyle = monoLight ? "#000000" : "#ffffff";
      else ctx.fillStyle = spikes ? "#ffe9a8" : "#ffffff";
      var capH = spikes ? 1 : 2
      for (var p = 0; p < n; p++) {
        var pv = _peakArr[p]
        if (pv < 0.02) continue
        var py = baseY - pv * areaH
        var px = p * (bw + gap)
        ctx.fillRect(px, py - 1, bw, capH)
      }
    }

    if (reflect) {
      // Floor mirror: faded copy of each bar below the baseline.
      ctx.save()
      ctx.globalAlpha = 0.22
      if (immersive) ctx.fillStyle = "#ffffff";
      else if (mono) ctx.fillStyle = monoLight ? "#000000" : "#ffffff";
      else ctx.fillStyle = fire ? fireColorAt(0.12) : themeBottom;
      for (var m = 0; m < n; m++) {
        var mv = silent ? 0 : Math.min(1, Math.max(0, b[m]) * sensitivity)
        var mh = mv * areaH * 0.5
        if (mh > 0) ctx.fillRect(m * (bw + gap), baseY + 2, bw + spikeOverlap, mh)
      }
      ctx.restore()
    }
  }

  function drawDots(ctx) {
    // Winamp skin backdrop: faint dot grid behind the bars.
    ctx.fillStyle = "rgba(255,255,255,0.05)"
    for (var x = 2; x < width; x += 6) {
      for (var y = 2; y < height; y += 6) {
        ctx.fillRect(x, y, 1, 1)
      }
    }
  }

  function drawWave(ctx) {
    // True oscilloscope: plots the engine's time-domain snippet when
    // present; falls back to the envelope synth on legacy frames.
    var w = wave
    ctx.lineWidth = Math.min(5, Math.max(1, scopeLineWidth))
    ctx.strokeStyle = fire ? fireColorAt(0.7) : fillFor(0.8, 0.9)
    ctx.beginPath()
    if (w && w.length > 1) {
      var mid = height * 0.5, amp = height * 0.42
      for (var i = 0; i < w.length; i++) {
        var x = i / (w.length - 1) * width
        var y = mid - Math.min(1, Math.max(-1, w[i])) * amp
        if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
      }
    } else {
      var b = displayBands()
      var n = b.length
      var mid2 = height * 0.5
      var step = Math.max(1, Math.floor(width / 220))
      for (var x2 = 0; x2 <= width; x2 += step) {
        var t = x2 / width
        var bi = Math.min(n - 1, Math.floor(t * n))
        var env = Math.min(1, b[bi]) * (0.35 + 0.65 * Math.sin(t * Math.PI))
        var y2 = mid2 - (height * 0.42) * env * Math.sin((x2 / width) * Math.PI * 6)
        if (x2 === 0) ctx.moveTo(x2, y2); else ctx.lineTo(x2, y2)
      }
    }
    ctx.stroke()
  }
}
