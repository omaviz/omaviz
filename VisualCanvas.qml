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
  property bool peaks: true
  property real peakFalloff: 0.5
  property bool spikes: false
  property bool fire: false
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
  property bool barColorCustom: false
  property color barColorFrom: "#e68e0d"
  property color barColorTo: "#f59e0b"
  // Oscilloscope feed: 128-point time-domain samples (-1..1, newest last).
  property var wave: []
  property real scopeLineWidth: 2
  // B&W mode (mini option): solid black on light themes, white on dark.
  // Takes precedence over Fire — an explicit monochrome choice.
  property bool mono: false
  property bool monoLight: false
  property bool artMode: false
  // Glow wash without the retired white-bar forcing: bound from the
  // Artwork-backdrop toggle (preview/desktop). artMode above stays for
  // old configs; new code sets wash instead.
  property bool wash: false
  // Artwork mode (Plexamp-style): reactive glow wash behind quiet
  // white bars. Foreground is always white; art (desktop-only Image
  // layer) sits behind the wash when available.
  // Winamp skin dressing: dotted backdrop (on) and floor reflection (off).
  property bool dots: false   // static DotsCanvas underlay owns the grid
  property bool reflect: false
  // Spike density cap: 0 = auto (~2px per bar across full width).
  // Mini passes 32 to keep its density down.
  property int spikeBars: 0
  property var _peakArr: []
  property var _peakSpeed: []

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

  // ---- Cached palette (perf): theme-derived colors rebuild only when
  // the theme signature changes — never per bar/frame. LUTs use the exact
  // same math as the old scalar versions (101 steps so gradient stops at
  // 0/0.25/1 land exactly), so pixels are identical while per-frame
  // QColor + string churn drops to ~zero.
  property var _palBot: [0, 0, 0]
  property var _palTop: [1, 1, 1]
  property var _fireLUT: []
  property var _plainLUT: []
  property var _washLUT: []
  property string _palSig: ""
  // Feed rate: the desktop bridge decimates to 30Hz (paints already
  // throttle there), while mini/preview stay 60. Peak physics runs two
  // substeps per arrival at 30Hz so cap trajectories match 60Hz.
  property real dataFps: 60
  // Peak-settled flag: when silent and every cap is parked, band updates
  // repaint an identical image — onBandsChanged skips those paints.
  property bool _peaksSettled: false
  // Scratch buffers so displayBands() doesn't allocate per frame.
  property var _bandBuf: []
  property var _bandUp: []

  function _rebuildPalette() {
    var bq = Qt.darker(barColorCustom ? barColorFrom : themeBottom, 1.25)
    var tq = Qt.lighter(barColorCustom ? barColorTo : (colorSync ? themeTop : Qt.color("#ffffff")), 1.2)
    _palBot = [bq.r, bq.g, bq.b]
    _palTop = [tq.r, tq.g, tq.b]
    var tipC = Qt.lighter(barColorCustom ? barColorTo : themeTop, 1.2)
    var tipR = Math.round(tipC.r * 255), tipG = Math.round(tipC.g * 255), tipB = Math.round(tipC.b * 255)
    var f = [], p = [], w = []
    for (var k = 0; k <= 100; k++) {
      var t = k / 100, r, g, bl
      if (t < 0.3) {
        var kc = t / 0.3
        r = Math.round(190 + kc * 65); g = Math.round(20 + kc * 110); bl = Math.round(kc * 10)
      } else {
        var k3 = (t - 0.3) / 0.7
        r = Math.round(255 + (tipR - 255) * k3)
        g = Math.round(130 + (tipG - 130) * k3)
        bl = Math.round(10 + (tipB - 10) * k3)
      }
      f.push("rgba(" + r + "," + g + "," + bl + ",1)")
      p.push("rgba(" + Math.round((_palBot[0] + (_palTop[0] - _palBot[0]) * t) * 255) + "," + Math.round((_palBot[1] + (_palTop[1] - _palBot[1]) * t) * 255) + "," + Math.round((_palBot[2] + (_palTop[2] - _palBot[2]) * t) * 255) + ",1)")
      w.push("rgba(" + Math.round((_palBot[0] + (_palTop[0] - _palBot[0]) * t) * 255) + "," + Math.round((_palBot[1] + (_palTop[1] - _palBot[1]) * t) * 255) + "," + Math.round((_palBot[2] + (_palTop[2] - _palBot[2]) * t) * 255) + ",0.10)")
    }
    _fireLUT = f; _plainLUT = p; _washLUT = w
  }

  function _lutIdx(t) {
    if (t <= 0) return 0
    if (t >= 1) return 100
    return Math.round(t * 100)
  }

  // Fire color at height fraction t (0 = base, 1 = tip): the base always
  // ignites from deep red; the tip lands on the active 2nd color — the
  // custom swatch To, or the live theme accent in theme mode — so theme
  // switches stay visible with Fire on.
  function fireColorAt(t) {
    return _fireLUT[_lutIdx(Math.min(1, Math.max(0, t)))]
  }

  // ---- Paint dedup (perf): peak physics advances on DATA arrival, then
  // the paint is skipped when the quantised pixel output would be
  // identical to the last painted frame. Skipped frames are pixel-equal
  // by construction — zero look change, large savings on steady passages.
  // Mode/toggle/resize handlers always repaint; stored sigs refresh after
  // every paint, so a later data frame repaints iff pixels would differ.
  // Paint stash (perf): _maybePaint already hashed this frame's pixels,
  // so onPaint reuses the hash instead of re-mapping + re-hashing. The
  // stash is valid only if no newer frame arrived before the paint
  // (_stashFrame === _frameId); staleness self-corrects (a mismatch just
  // repaints once, then converges — never freezes).
  property double _stashSig: -1
  property string _stashMode: ""
  property bool _stashValid: false
  property int _frameId: 0
  property int _stashFrame: -1
  // Last painted frame identity (dedup baseline).
  // (double, not int: FNV-1a hashes exceed signed 32-bit range.)
  property double _lastBandsSig: -1
  property string _lastModeSig: ""

  function _sizePeaks(n) {
    if (_peakArr.length !== n) {
      _peakArr = []
      for (var p = 0; p < n; p++) _peakArr.push(0)
    }
    if (_peakSpeed.length !== n) {
      _peakSpeed = []
      var s0 = (1.5 + peakFalloff * 6.5) / 256
      for (var s = 0; s < n; s++) _peakSpeed.push(s0)
    }
  }

  function _advancePhysics(b, n) {
    _sizePeaks(n)
    // Winamp peak physics: caught peaks reset a slow drop speed that
    // accelerates ×1.05/frame — hang, then snap down (not linear decay).
    // falloff maps to initial drop speed (~1.5/256 → ~8/256 per frame).
    // At 30Hz feeds each arrival advances two substeps on the same sample
    // (catch is idempotent, decay doubles) to track the 60Hz trajectory.
    var speed0 = (1.5 + peakFalloff * 6.5) / 256
    var steps = dataFps > 45 ? 1 : 2
    for (var st = 0; st < steps; st++) {
      for (var i = 0; i < n; i++) {
        var v = silent ? 0 : Math.min(1, Math.max(0, b[i]) * sensitivity)
        if (v >= _peakArr[i]) { _peakArr[i] = v; _peakSpeed[i] = speed0 }
        else {
          _peakArr[i] = Math.max(0, _peakArr[i] - _peakSpeed[i])
          _peakSpeed[i] = _peakSpeed[i] * 1.05
        }
      }
    }
    var settledNow = silent === true
    if (settledNow) {
      for (var q = 0; q < n; q++) {
        if (_peakArr[q] >= 0.02) { settledNow = false; break }
      }
    }
    _peaksSettled = settledNow
  }

  function _modeSig() {
    return visual + "|" + (reflect ? 1 : 0) + "|" + (spikes ? 1 : 0) + "|" + (fire ? 1 : 0) + "|" + (stacks ? 1 : 0) + "|" + (peaks ? 1 : 0) + "|" + (mono ? 1 : 0) + "|" + (monoLight ? 1 : 0) + "|" + (artMode ? 1 : 0) + "|" + (wash ? 1 : 0) + "|" + (dots ? 1 : 0) + "|" + gapPx + "|" + peakFalloff + "|" + stackScale + "|" + barCount + "|" + spikeBars + "|" + scopeLineWidth + "|" + sensitivity + "|" + (silent ? 1 : 0) + "|" + _palSig
  }

  function _computeSig(b, n) {
    // FNV-1a over pixel-quantised heights: identical hash + identical
    // mode/geometry/palette ⇒ identical raster.
    var areaH = reflect ? height * 0.62 : height
    var hsh = 2166136261
    if (visual === "Wave" || visual === "Oscilloscope") {
      var w = wave
      var wn = w ? w.length : 0
      for (var k = 0; k < wn; k++) {
        var wv = Math.round(Math.min(1, Math.max(-1, w[k])) * areaH)
        hsh ^= (wv & 0xffff); hsh = Math.imul(hsh, 16777619) >>> 0
      }
      return hsh
    }
    for (var i = 0; i < n; i++) {
      var v = silent ? 0 : Math.min(1, Math.max(0, b[i]) * sensitivity)
      hsh ^= (Math.round(v * areaH) & 0xffff); hsh = Math.imul(hsh, 16777619) >>> 0
      hsh ^= (Math.round((_peakArr[i] || 0) * areaH) & 0xffff); hsh = Math.imul(hsh, 16777619) >>> 0
    }
    return hsh
  }

  // Paint throttle (perf): motion slower than ~30fps reads as smooth for
  // spectrum bars (Winamp-class cadence). Physics still advances on every
  // 60Hz data frame, so trajectories stay exact — paints just sample them
  // at 30Hz. Toggle/resize/mode handlers bypass the throttle (direct
  // requestPaint) so UI feedback stays instant.
  property double _lastPaintMs: 0

  function _maybePaint(b, n) {
    if (!n) return
    var now = Date.now()
    if (now - _lastPaintMs < 33) return
    var bs = _computeSig(b, n)
    var ms = _modeSig()
    if (bs === _lastBandsSig && ms === _lastModeSig) return
    _lastPaintMs = now
    _stashSig = bs; _stashMode = ms; _stashFrame = _frameId; _stashValid = true
    requestPaint()
  }

  onBandsChanged: {
    // Wave mode ignores spectrum frames (scope paints from wave only).
    if (visual === "Wave" || visual === "Oscilloscope") return
    _frameId++
    var b = displayBands()
    var n = b.length
    if (!n) { requestPaint(); return }
    _advancePhysics(b, n)
    _maybePaint(b, n)
  }
  onBarCountChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()
  onWaveChanged: {
    if (visual !== "Wave" && visual !== "Oscilloscope") return
    _frameId++
    var wv = wave
    _maybePaint(wv, wv ? wv.length : 0)
  }
  onDotsChanged: requestPaint()
  onReflectChanged: requestPaint()
  onSpikesChanged: requestPaint()
  onFireChanged: requestPaint()
  onStacksChanged: requestPaint()
  onStackScaleChanged: requestPaint()
  onSensitivityChanged: requestPaint()
  onThemeBottomChanged: requestPaint()
  onThemeTopChanged: requestPaint()
  onVisualChanged: requestPaint()
  onPeaksChanged: requestPaint()
  onPeakFalloffChanged: requestPaint()
  onScopeLineWidthChanged: requestPaint()
  onMonoChanged: requestPaint()
  onMonoLightChanged: requestPaint()
  onArtModeChanged: requestPaint()
  onWashChanged: requestPaint()
  onBarColorCustomChanged: requestPaint()
  onBarColorFromChanged: requestPaint()
  onBarColorToChanged: requestPaint()

  function fillFor(h, a) {
    if (artMode) return "#ffffff"
    if (mono) return monoLight ? "#000000" : "#ffffff"
    // Fire ramp (custom-aware tip) — Winamp flame, kept luminous at low
    // levels so quiet bars stay visible on dark containers.
    if (fire) return fireColorAt(h)
    // Custom tones win over theme; otherwise theme-anchored: colorSync
    // blends bottom→top theme colors, otherwise bottom rises toward
    // white-hot with bar height. Base pushed darker, tip lighter for a
    // stronger gradient read. (LUT: same math, quantized — pixel-equal.)
    return _plainLUT[_lutIdx(Math.min(1, Math.max(0, h)))]
  }

  function fillWash(h) {
    return _washLUT[_lutIdx(Math.min(1, Math.max(0, h)))]
  }

  onPaint: {
    var ctx = getContext("2d")
    ctx.clearRect(0, 0, width, height)
    // NOTE: dots defaults false — surfaces use the static DotsCanvas
    // underlay (per-frame dots cost ~34K rects on a big desktop).
    if (dots) drawDots(ctx)
    var b = displayBands()
    var n = b.length
    if (!n) return
    // Palette refresh (theme-bound only): drawWave below already needs it.
    var sig = themeBottom + "|" + themeTop + "|" + barColorFrom + "|" + barColorTo + "|" + (barColorCustom ? 1 : 0) + "|" + (colorSync ? 1 : 0)
    if (sig !== _palSig) { _palSig = sig; _rebuildPalette() }
    if (visual === "Wave" || visual === "Oscilloscope") { drawWave(ctx); return }
    // Reflection zone: bars live in the top ~2/3 anchored at baseY, the
    // mirror fades below. Otherwise the full height is the bar area.
    var areaH = reflect ? height * 0.62 : height
    var baseY = reflect ? height * 0.68 : height
    if (artMode || wash) {
      // Overlap-free wash (perf): each wash rect is 2x bar width, so every
      // interior column is blended TWICE. Adjacent rects share one alpha,
      // so each column's stacked result is computed analytically and
      // painted ONCE — same stacked color (±1 LSB from single vs double
      // 8-bit rounding), half the blend area. Columns emit pairwise in one
      // pass (O(1) extra memory); the tail column has a single cover.
      var wa = 0.10
      var wao = 1 - (1 - wa) * (1 - wa)   // stacked alpha of two covers
      var gw = width / n
      var prvR = 0, prvG = 0, prvB = 0, prvH = 0, prvStyle = "", hasPrv = false
      for (var g = 0; g < n; g++) {
        var gv = silent ? 0 : Math.min(1, Math.max(0, b[g]) * sensitivity)
        var curR, curG, curB, curStyle
        if (fire) {
          curR = 255; curG = Math.round(120 + gv * 120); curB = 60
          curStyle = "rgba(255," + curG + ",60,0.10)"
        } else {
          // Quantized t matches _washLUT (used for slivers/singles below)
          // so combined columns and slivers agree exactly.
          var wt = _lutIdx(gv) / 100
          curR = Math.round((_palBot[0] + (_palTop[0] - _palBot[0]) * wt) * 255)
          curG = Math.round((_palBot[1] + (_palTop[1] - _palBot[1]) * wt) * 255)
          curB = Math.round((_palBot[2] + (_palTop[2] - _palBot[2]) * wt) * 255)
          curStyle = fillWash(gv)
        }
        var curH = Math.max(2, gv * height)
        if (hasPrv) {
          // Column [(g-1)*gw, g*gw): bottom min() blends both covers,
          // the taller cover owns the sliver above it.
          var colX = (g - 1) * gw
          var comH = Math.min(prvH, curH)
          var cmbR = Math.round((curR * wa + prvR * wa * (1 - wa)) / wao)
          var cmbG = Math.round((curG * wa + prvG * wa * (1 - wa)) / wao)
          var cmbB = Math.round((curB * wa + prvB * wa * (1 - wa)) / wao)
          ctx.fillStyle = "rgba(" + cmbR + "," + cmbG + "," + cmbB + "," + wao + ")"
          ctx.fillRect(colX, height - comH, gw, comH)
          if (curH > prvH) {
            ctx.fillStyle = curStyle
            ctx.fillRect(colX, height - curH, gw, curH - prvH)
          } else if (prvH > curH) {
            ctx.fillStyle = prvStyle
            ctx.fillRect(colX, height - prvH, gw, prvH - curH)
          }
        }
        prvR = curR; prvG = curG; prvB = curB; prvH = curH; prvStyle = curStyle; hasPrv = true
      }
      // Tail column [(n-1)*gw, width]: covered by the last rect alone.
      var tailX = (n - 1) * gw
      ctx.fillStyle = prvStyle
      ctx.fillRect(tailX, height - prvH, width - tailX, prvH)
    }

    var gap = spikes ? 0 : gapPx
    var totalGap = gap * (n - 1)
    var bw = spikes ? Math.max(1, width / n) : Math.max(2, (width - totalGap) / n)
    // Spike overlap: fractional widths leave 1px container seams between
    // bars — draw each spike half a pixel wider to seal them.
    var spikeOverlap = spikes ? 0.5 : 0

    // Peak buffers track the band count (sized on data; this guard covers
    // paints that precede data, e.g. first paint or resize without frames).
    // Physics itself advances in _advancePhysics on data arrival — paints
    // never move the simulation (see paint-dedup note at the handlers).
    if (_peakArr.length !== n) {
      _peakArr = []
      for (var p = 0; p < n; p++) _peakArr.push(0)
    }
    if (_peakSpeed.length !== n) {
      _peakSpeed = []
      var _sp0 = (1.5 + peakFalloff * 6.5) / 256
      for (var s = 0; s < n; s++) _peakSpeed.push(_sp0)
    }
    // Flat-fill fast path (mono/artMode): every body shares one fillStyle,
    // so all bodies join a single path + one fill instead of N fills.
    var useFlat = mono || artMode
    var flatFill = artMode ? "#ffffff" : (monoLight ? "#000000" : "#ffffff")
    // One shared fire gradient per frame (identical coords for every bar).
    var sharedGrad = null
    if (!useFlat && fire) {
      sharedGrad = ctx.createLinearGradient(0, baseY, 0, baseY - areaH)
      sharedGrad.addColorStop(0, fireColorAt(0))
      sharedGrad.addColorStop(0.25, fireColorAt(0.25))
      sharedGrad.addColorStop(1, fireColorAt(1))
    }
    if (useFlat) { ctx.fillStyle = flatFill; ctx.beginPath() }
    // Batched plain bars (perf): opaque gap-separated bodies are paint-
    // order independent, so one path+fill per quantized color paints
    // bit-exact pixels with ~6x fewer fillStyle/fill calls than one fill
    // per bar. (Fire keeps its shared gradient; stacks/spikes keep their
    // per-bar paths — only this branch batches.)
    var barBkt = {}, barOrd = []

    for (var i = 0; i < n; i++) {
      // Values only — physics already advanced on data arrival.
      var v = silent ? 0 : Math.min(1, Math.max(0, b[i]) * sensitivity)
      var h = v * areaH
      // Auto floor (Min-height toggle retired): 1px while playing so
      // quiet bars stay visible, 0 when silent so idle bars vanish.
      var floorH = silent ? 0 : 1
      if (h < floorH) h = floorH
      var x = i * (bw + gap)
      var y = baseY - h
      if (h <= 0) continue
      if (stacks) {
        // Winamp segments: 3px blocks with 1px gaps, stacked from the base.
        // Each block samples the fire ramp (or flat fill) at its own height
        // so the red-to-hot gradient climbs the bar like a real flame.
        // stackScale 2 (desktop) doubles block + gap, keeping proportions.
        var segH = 3 * stackScale, segGap = 1 * stackScale, sy = baseY
        while (sy > y) {
          var sh = Math.min(segH, sy - y)
          if (useFlat) ctx.rect(x, sy - sh, bw + spikeOverlap, sh)
          else {
            var tMid = 1 - (sy - sh / 2 - (baseY - areaH)) / areaH
            if (fire) ctx.fillStyle = fireColorAt(tMid);
            else ctx.fillStyle = fillFor(v, 0.25 + v * 0.75);
            ctx.fillRect(x, sy - sh, bw + spikeOverlap, sh)
          }
          sy -= segH + segGap
        }
        if (spikes) {
          if (useFlat) {
            ctx.moveTo(x, y)
            ctx.lineTo(x + bw + spikeOverlap, y)
            ctx.lineTo(x + bw / 2, Math.max(0, y - Math.min(bw, 5)))
          } else {
            ctx.beginPath()
            ctx.moveTo(x, y)
            ctx.lineTo(x + bw + spikeOverlap, y)
            ctx.lineTo(x + bw / 2, Math.max(0, y - Math.min(bw, 5)))
            ctx.closePath()
            ctx.fill()
          }
        }
      } else if (spikes) {
        // Pointed tip: sharp triangle apex over a square body.
        // Fire: vertical red-to-hot gradient along the bar area.
        var tipH = Math.min(Math.max(bw, 3), 7)
        if (useFlat) {
          if (h > tipH + 1) {
            ctx.rect(x, y + tipH, bw + spikeOverlap, h - tipH)
            ctx.moveTo(x, y + tipH)
            ctx.lineTo(x + bw + spikeOverlap, y + tipH)
            ctx.lineTo(x + bw / 2, y)
          } else {
            ctx.moveTo(x, y + h)
            ctx.lineTo(x + bw + spikeOverlap, y + h)
            ctx.lineTo(x + bw / 2, y)
          }
        } else {
          if (fire) ctx.fillStyle = sharedGrad
          else ctx.fillStyle = fillFor(v, 0.25 + v * 0.75)
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
        }
      } else if (useFlat) {
        var r = Math.min(bw * 0.5, 3)
        if (ctx.roundRect) ctx.roundRect(x, y, bw, h, r); else ctx.rect(x, y, bw, h)
      } else if (fire) {
        ctx.fillStyle = sharedGrad
        ctx.beginPath()
        var r2 = Math.min(bw * 0.5, 3)
        if (ctx.roundRect) ctx.roundRect(x, y, bw, h, r2); else ctx.rect(x, y, bw, h)
        ctx.fill()
      } else {
        // Collect into the color bucket — flushed as one fill per color
        // after the loop (bit-exact: same rects, same fill, fewer calls).
        // v is already clamped 0..1 above, matching fillFor's LUT index.
        var bkey = _lutIdx(v)
        var barr = barBkt[bkey]
        if (barr === undefined) { barr = []; barBkt[bkey] = barr; barOrd.push(bkey) }
        barr.push(x, y, h)
      }
    }
    if (useFlat) ctx.fill()
    else if (barOrd.length > 0) {
      var hasRR = !!ctx.roundRect
      var brad = Math.min(bw * 0.5, 3)
      for (var bi2 = 0; bi2 < barOrd.length; bi2++) {
        var bk2 = barOrd[bi2], ba = barBkt[bk2]
        ctx.fillStyle = _plainLUT[bk2]
        ctx.beginPath()
        for (var bj = 0; bj < ba.length; bj += 3) {
          if (hasRR) ctx.roundRect(ba[bj], ba[bj + 1], bw, ba[bj + 2], brad)
          else ctx.rect(ba[bj], ba[bj + 1], bw, ba[bj + 2])
        }
        ctx.fill()
      }
    }

    if (peaks) {
      // Thin-spike caps: 1px hot ticks (a 2px block would swallow a 2px bar).
      // Mono: caps match the bars (ticks sit on the background above them).
      // Single shared path + one fill — same pixels as N fillRects.
      if (artMode) ctx.fillStyle = "#ffffff";
      else if (mono) ctx.fillStyle = monoLight ? "#000000" : "#ffffff";
      else ctx.fillStyle = spikes ? "#ffe9a8" : "#ffffff";
      var capH = spikes ? 1 : 2
      ctx.beginPath()
      for (var p = 0; p < n; p++) {
        var pv = _peakArr[p]
        if (pv < 0.02) continue
        var py = baseY - pv * areaH
        var px = p * (bw + gap)
        ctx.rect(px, py - 1, bw, capH)
      }
      ctx.fill()
    }

    if (reflect) {
      // Floor mirror: faded copy of each bar below the baseline, tinted
      // with the bar base color (custom From, else theme) so it tracks
      // the bars. Mono/artMode mirrors match their white/black bars.
      // Batched into one path + one fill (same fillStyle throughout).
      ctx.save()
      ctx.globalAlpha = 0.22
      if (artMode) ctx.fillStyle = "#ffffff";
      else if (mono) ctx.fillStyle = monoLight ? "#000000" : "#ffffff";
      else ctx.fillStyle = fire ? fireColorAt(0.12) : Qt.darker(barColorCustom ? barColorFrom : themeBottom, 1.25);
      ctx.beginPath()
      for (var m = 0; m < n; m++) {
        var mv = silent ? 0 : Math.min(1, Math.max(0, b[m]) * sensitivity)
        var mh = mv * areaH * 0.5
        if (mh > 0) ctx.rect(m * (bw + gap), baseY + 2, bw + spikeOverlap, mh)
      }
      ctx.fill()
      ctx.restore()
    }

    // Paint dedup bookkeeping: remember exactly what hit the pixels, so
    // the next data frame can prove itself different (or skip the paint).
    // Stash reuse: when this paint was requested for the newest frame,
    // _maybePaint already hashed it — no second mapping+hash.
    _stashValid = false
    if (_stashFrame === _frameId && _stashSig !== -1) {
      _lastBandsSig = _stashSig
      _lastModeSig = _stashMode
    } else {
      var _sb = displayBands()
      _lastBandsSig = _computeSig(_sb, _sb.length)
      _lastModeSig = _modeSig()
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
