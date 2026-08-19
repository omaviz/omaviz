// glspectrum.js — shared spectrum → GPU uniform packing.
//
// Plain global functions so QML can `import "glspectrum.js" as GL`.
// A node-only `module.exports` guard at the bottom lets the same file be
// unit-tested under node (TDD), since QML JS imports ignore module.exports.

// Pack a variable-length `bands` spectrum into a fixed-length array of `n`
// normalized [0,1] floats for a GLSL `uniform float u_bands[n]`.
// Downsamples (nearest) when bands is longer than n; pads with 0 when shorter.
// Out-of-range values are clamped so a bad frame can never poison the shader.
function packBands(bands, n) {
  var out = []
  for (var i = 0; i < n; i++) out.push(0)
  if (!bands || bands.length === 0) return out
  for (var j = 0; j < n; j++) {
    var srcIdx = Math.floor((j * bands.length) / n)
    if (srcIdx >= bands.length) srcIdx = bands.length - 1
    var v = bands[srcIdx]
    if (typeof v !== "number" || isNaN(v)) v = 0
    if (v < 0) v = 0
    if (v > 1) v = 1
    out[j] = v
  }
  return out
}

// Peak value across the packed array (used to drive glow/beat in the shader).
function peakOf(packed) {
  var m = 0
  for (var i = 0; i < packed.length; i++) if (packed[i] > m) m = packed[i]
  return m
}

// Fire toggle -> control-texture row 8 value, mirroring VisualCanvasGL.qml
// (cFire*255) and visual.frag (fireOn(): fireRow().r > 0.5). 1.0 == on.
function packFire(fire) { return fire ? 1.0 : 0.0 }
function fireOn(packed) { return packed > 0.5 }

// Bar-gap control -> control-texture row 11 G value (0..1 of one bar slot),
// mirroring VisualCanvasGL.qml (Math.round(clamp(barGap,0,1)*255)) and
// visual.frag (gap() = clamp(scopeRow().g, 0.0, 0.9)). 0 = contiguous.
function packGap(gap) {
  if (typeof gap !== "number" || isNaN(gap)) gap = 0
  if (gap < 0) gap = 0
  if (gap > 1) gap = 1
  return gap
}
function gapOf(packed) { return packed > 0.5 ? 1.0 : packed }

if (typeof module !== "undefined" && module.exports) {
  module.exports = { packBands: packBands, peakOf: peakOf, packFire: packFire, fireOn: fireOn, packGap: packGap, gapOf: gapOf }
}
