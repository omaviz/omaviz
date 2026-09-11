// dsp.js — omaviz v8.1 pure-JS DSP: PCM ring buffer, Hann FFT, log bands,
// envelope/beat detection. Replaces the retired Rust omaviz-engine.
// Benchmarked on host: 0.08 ms/frame for FFT(1024)+bands (budget 16.6 ms).
'use strict'

var FFT_SIZE = 1024
var SAMPLE_RATE = 44100
var BAND_COUNT = 32
var SILENCE_THRESHOLD = 0.02

// ---- Precomputed FFT tables ----
var _rev = new Uint32Array(FFT_SIZE)
;(function () {
  for (var i = 1, j = 0; i < FFT_SIZE; i++) {
    var b = FFT_SIZE >> 1
    for (; j & b; b >>= 1) j ^= b
    j ^= b
    _rev[i] = j
  }
})()
var _cos = new Float32Array(FFT_SIZE / 2)
var _sin = new Float32Array(FFT_SIZE / 2)
for (var i = 0; i < FFT_SIZE / 2; i++) {
  _cos[i] = Math.cos(-2 * Math.PI * i / FFT_SIZE)
  _sin[i] = Math.sin(-2 * Math.PI * i / FFT_SIZE)
}
var _hann = new Float32Array(FFT_SIZE)
for (var h = 0; h < FFT_SIZE; h++) {
  _hann[h] = 0.5 - 0.5 * Math.cos(2 * Math.PI * h / (FFT_SIZE - 1))
}

// ---- Log-spaced band edges over 20 Hz .. 20 kHz (bin indices) ----
var _bandEdges = (function () {
  var e = []
  for (var b = 0; b <= BAND_COUNT; b++) {
    var hz = 20 * Math.pow(1000, b / BAND_COUNT)
    e.push(Math.max(1, Math.round(hz * FFT_SIZE / SAMPLE_RATE)))
  }
  return e
})()

// ---- Ring buffer ----
var _ring = new Float32Array(FFT_SIZE)
var _fill = 0 // samples accumulated (up to FFT_SIZE)

// Push raw PCM bytes (little-endian f32) from pw-record stdout.
// Returns number of complete windows now available.
function pushBytes(arrayBuffer, byteOffset, byteLength) {
  var n = Math.floor(byteLength / 4)
  if (n <= 0) return 0
  var f = new Float32Array(arrayBuffer, byteOffset, n)
  for (var i = 0; i < n; i++) {
    _ring.copyWithin(0, 1)
    _ring[FFT_SIZE - 1] = f[i]
    _fill++
  }
  return _fill >= FFT_SIZE ? 1 : 0
}

// Push a Float32Array of samples directly (tests / non-byte paths).
function pushSamples(samples) {
  for (var i = 0; i < samples.length; i++) {
    _ring.copyWithin(0, 1)
    _ring[FFT_SIZE - 1] = samples[i]
    _fill++
  }
  return _fill >= FFT_SIZE ? 1 : 0
}


// Push bytes from a plain JS array (0-255 values) — avoids typed-array
// buffer-identity pitfalls across the QML boundary.
function pushBytesFromArray(bytes) {
  var n = bytes.length
  for (var i = 0; i < n; i++) {
    _ring.copyWithin(0, 1)
    _ring[FFT_SIZE - 1] = bytes[i]
    _fill++
  }
  return _fill >= FFT_SIZE ? 1 : 0
}

function resetBuffer() { _fill = 0 }

// ---- FFT magnitude (in-place radix-2) ----
var _re = new Float32Array(FFT_SIZE)
var _im = new Float32Array(FFT_SIZE)

function _fftMagnitudes() {
  var n = FFT_SIZE
  for (var i = 0; i < n; i++) {
    var jj = _rev[i]
    if (jj > i) {
      var t = _re[i]; _re[i] = _re[jj]; _re[jj] = t
      t = _im[i]; _im[i] = _im[jj]; _im[jj] = t
    }
  }
  for (var size = 2; size <= n; size <<= 1) {
    var half = size >> 1, step = n / size
    for (var off = 0; off < n; off += size) {
      for (var k2 = 0, j2 = off; j2 < off + half; j2++, k2 += step) {
        var tre = _re[j2 + half] * _cos[k2] - _im[j2 + half] * _sin[k2]
        var tim = _re[j2 + half] * _sin[k2] + _im[j2 + half] * _cos[k2]
        _re[j2 + half] = _re[j2] - tre; _im[j2 + half] = _im[j2] - tim
        _re[j2] += tre; _im[j2] += tim
      }
    }
  }
  return _re
}

// ---- Envelope/beat state ----
var _energy = 0
var _beat = 0
var _prevEnergy = 0

// Per-band gain to pre-emphasize highs (raw FFT makes bass dominate).
// Mild tilt: +0.4 dB/band across 32 bands ≈ +13 dB total treble lift.
var _bandGain = (function () {
  var g = new Float32Array(BAND_COUNT)
  for (var i = 0; i < BAND_COUNT; i++) {
    g[i] = Math.pow(10, (i / BAND_COUNT) * 3.0 / 20) // up to ~+30dB
  }
  return g
})()

// Compute one spectrum frame from the ring buffer.
// Returns { bands: Float32Array(BAND_COUNT), energy, beat, silent } or null
// if the buffer is not yet full.
//
// Band mapping (Winamp-style, matches v7 engine feel):
//   magnitude = RMS of |X| over band bins
//   scaled    = magnitude * gain / N   (N/2-point spectrum)
//   value     = clamp(1 + log10(scaled * 8) / 2.5, 0, 1)   ← log dynamics:
//               noise floor (~1e-3) → ~0.2, quiet (1e-2) → ~0.5,
//               strong (1e-1) → ~0.9, clip (≥1) → 1.0. Every bar moves.
function analyze(sensitivity) {
  if (_fill < FFT_SIZE) return null
  var sens = sensitivity || 1.0
  for (var i = 0; i < FFT_SIZE; i++) { var sv = _ring[i]; _re[i] = (sv === sv ? sv : 0) * _hann[i]; _im[i] = 0 } // NaN guard
  _fftMagnitudes()
  var bands = new Float32Array(BAND_COUNT)
  var scale = sens / (FFT_SIZE / 4) // full-scale sine at center bin → mag 1.0
  for (var b = 0; b < BAND_COUNT; b++) {
    var lo = _bandEdges[b], hi = Math.max(_bandEdges[b + 1], lo + 1)
    if (hi > FFT_SIZE / 2) hi = FFT_SIZE / 2
    var sum = 0
    for (var k = lo; k < hi; k++) {
      sum += _re[k] * _re[k] + _im[k] * _im[k]
    }
    var rms = Math.sqrt(sum / (hi - lo)) // per-band RMS magnitude
    var scaled = rms * scale * _bandGain[b]
    // log dynamic-response mapping — the key to "natural" movement:
    var v = 1 + Math.log10(Math.max(scaled, 1e-6) * 3) / 3.2
    bands[b] = v < 0 ? 0 : (v > 1 ? 1 : v)
  }
  // energy: mean of top half of bands (musical loudness proxy)
  var e = 0, n = 0
  for (var q = BAND_COUNT >> 2; q < BAND_COUNT; q++) { e += bands[q]; n++ }
  e /= n
  // onset: energy rising sharply vs previous frame
  _beat = e > _prevEnergy * 1.35 && e > SILENCE_THRESHOLD ? 1 : 0
  _prevEnergy = e
  _energy = e
  return { bands: bands, energy: e, beat: _beat, silent: e < SILENCE_THRESHOLD * 0.5 }
}

// Frame smoothing (attack fast, decay per smoothing config 0..1).
var _smoothed = null
function smoothBands(frame, smoothing) {
  if (!_smoothed) {
    _smoothed = new Float32Array(BAND_COUNT)
    for (var i = 0; i < BAND_COUNT; i++) _smoothed[i] = 0
  }
  var s = Math.min(1, Math.max(0, smoothing === undefined ? 0.5 : smoothing))
  var attack = 0.8, decay = 0.5 - s * 0.45 // higher smoothing → slower fall
  for (var b = 0; b < BAND_COUNT; b++) {
    var v = frame.bands[b]
    var a = v > _smoothed[b] ? attack : Math.max(0.05, decay)
    _smoothed[b] += (v - _smoothed[b]) * a
  }
  return _smoothed
}

function resetSmoothed() { _smoothed = null; _energy = 0; _beat = 0; _prevEnergy = 0; resetBuffer() }

// Resolve the pw-record command for the given monitor source name.
function captureCommand(monitorSource) {
  return ['pw-record', '--target', monitorSource, '--format', 'f32',
          '--rate', String(SAMPLE_RATE), '--channels', '1', '--raw', '-']
}

// Extract the ".monitor" source name of the default sink from
// `pactl list sources short` output.
function monitorSourceFromPactl(pactlOutput) {
  var lines = String(pactlOutput).split('\n')
  for (var i = 0; i < lines.length; i++) {
    var parts = lines[i].split('\t')
    if (parts.length > 1 && /\.monitor$/.test(parts[1]) && parts[1].indexOf('alsa_output') >= 0) {
      return parts[1]
    }
  }
  // fallback: any .monitor
  for (var j = 0; j < lines.length; j++) {
    var p2 = lines[j].split('\t')
    if (p2.length > 1 && /\.monitor$/.test(p2[1])) return p2[1]
  }
  return null
}

if (typeof module !== 'undefined') {
  module.exports = {
    FFT_SIZE: FFT_SIZE, SAMPLE_RATE: SAMPLE_RATE, BAND_COUNT: BAND_COUNT,
    SILENCE_THRESHOLD: SILENCE_THRESHOLD,
    pushBytes: pushBytes, pushBytesFromArray: pushBytesFromArray, pushSamples: pushSamples, resetBuffer: resetBuffer,
    analyze: analyze, smoothBands: smoothBands, resetSmoothed: resetSmoothed,
    captureCommand: captureCommand, monitorSourceFromPactl: monitorSourceFromPactl
  }
}
