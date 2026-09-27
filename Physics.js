.pragma library

// Physics.js — pure per-band visual physics for omaviz.
//
// Extracted from VisualCanvas.qml so the motion model is UNIT-TESTABLE under
// node (tests/physics.test.cjs) instead of being verified by eye. VisualCanvas
// imports this module and owns no physics math of its own — every surface
// (mini bar, panel preview, desktop window, oscilloscope) therefore shares the
// exact same fall/peak behavior.
//
// Model (Winamp-class):
//   * instant attack  — the bar jumps to the new target on the same frame
//   * rate-limited release — the bar falls toward the target at a bounded
//     speed, so when audio stops the bars FALL instead of vanishing
//   * peak caps — the cap rides above the bar, HOLDS at the top for
//     peakSustainMs, then falls with an accelerating speed (x1.05/frame):
//     a hang, then a snap down
//
// All functions are pure and mutate caller-owned arrays by index, so QML can
// keep flat scratch buffers and avoid per-frame allocation.
//
// Rates are expressed per SECOND; callers pass a fixed dt (ms) per frame.

// Initial peak-cap drop speed (units/frame) for a given falloff control 0..1.
// Kept identical to the v8 scalar formula for visual continuity.
function peakSpeed0(falloff) {
  var f = falloff
  if (f !== f) f = 0.1
  if (f < 0) f = 0
  if (f > 1) f = 1
  return (0.5 + f * 4.5) / 256
}

// Bar release speed (units/second). Independent of, but related to, the peak
// falloff: the same 0..1 control drives both, with different constants.
function barFallRate(falloff) {
  var f = falloff
  if (f !== f) f = 0.1
  if (f < 0) f = 0
  if (f > 1) f = 1
  return 0.5 + f * 4.5
}

// Exponential ease-out constant (1/second) for non-linear release.
var EASE_K = 6.0

// Allocate/trim the parallel state arrays to length n, preserving values.
function ensure(arr, n, fill) {
  if (arr.length === n) return arr
  var out = new Array(n)
  for (var i = 0; i < n; i++) out[i] = i < arr.length ? arr[i] : fill
  return out
}

// Clamp helper (QML's Math.min/max are fine, but keep one definition).
function clamp01(v) {
  if (v !== v) return 0
  return v < 0 ? 0 : (v > 1 ? 1 : v)
}

// Advance ONE frame of physics.
//   bars    : rendered bar heights (mutated)
//   peaks   : cap heights (mutated)
//   holds   : remaining sustain frames per cap (mutated)
//   speeds  : current cap drop speed per cap (mutated)
//   targets : raw engine band values (already sensitivity-scaled), 0..1
//   dtMs    : frame delta in ms
//   opts    : { linearFall, peakFalloff, peakSustainMs, noiseFloor }
function step(bars, peaks, holds, speeds, targets, dtMs, opts) {
  var n = targets.length
  var dt = dtMs / 1000
  var rate = barFallRate(opts.peakFalloff)
  var speed0 = peakSpeed0(opts.peakFalloff)
  var sustain = Math.round((opts.peakSustainMs || 0) / dtMs)
  var floor = opts.noiseFloor || 0
  var linear = opts.linearFall !== false
  for (var i = 0; i < n; i++) {
    var t = targets[i]
    if (t !== t) t = 0
    if (t < floor) t = 0
    t = clamp01(t)

    // ---- bar envelope: instant attack, rate-limited release ----
    var cur = bars[i]
    if (cur !== cur) cur = 0
    if (t >= cur) {
      cur = t
    } else if (linear) {
      var next = cur - rate * dt
      cur = next > t ? next : t
    } else {
      var eased = cur - (cur - t) * (1 - Math.exp(-EASE_K * dt))
      cur = eased > t ? eased : t
    }
    bars[i] = cur

    // ---- peak cap: ride, hold, then accelerate down ----
    if (cur >= peaks[i]) {
      peaks[i] = cur
      holds[i] = sustain
      speeds[i] = speed0
    } else if (holds[i] > 0) {
      holds[i] = holds[i] - 1
    } else {
      var p = peaks[i] - speeds[i]
      if (p < cur) p = cur
      peaks[i] = p
      speeds[i] = speeds[i] * 1.05
    }
  }
}

// True when nothing is left to animate: every bar is at its target and every
// cap is parked at/below the bar. Lets the renderer idle (stop repainting).
function settled(bars, peaks, targets, epsilon) {
  var eps = epsilon || 0.002
  var n = targets.length
  for (var i = 0; i < n; i++) {
    if (bars[i] > targets[i] + eps || bars[i] < targets[i] - eps) return false
    if (peaks[i] > bars[i] + eps) return false
  }
  return true
}

if (typeof module !== "undefined") {
  module.exports = {
    peakSpeed0: peakSpeed0,
    barFallRate: barFallRate,
    ensure: ensure,
    clamp01: clamp01,
    step: step,
    settled: settled,
    EASE_K: EASE_K
  }
}
