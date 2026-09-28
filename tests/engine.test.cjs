// Engine integration tests — run: node --test tests/engine.test.cjs
//
// These exercise the REAL compiled binary (bin/omaviz-engine), not a mock:
// spawn it against the deterministic built-in generator, read its stdout, and
// assert the frame contract the plugin parses. This is the test that proves
// the engine actually emits raw, 60Hz, well-formed frames.
"use strict"
const fs = require("fs")
const path = require("path")
const { test } = require("node:test")
const assert = require("node:assert/strict")
const { spawn } = require("node:child_process")

const BIN = path.join(__dirname, "..", "bin", "omaviz-engine")
const HAVE_BIN = fs.existsSync(BIN)

// Spawn the engine, collect parsed frames for `ms`, then kill it.
function collect(args, ms) {
  return new Promise((resolve) => {
    const p = spawn(BIN, args, { stdio: ["ignore", "pipe", "ignore"] })
    let buf = ""
    const frames = []
    p.stdout.on("data", (d) => {
      buf += d.toString()
      let i
      while ((i = buf.indexOf("\n")) >= 0) {
        const line = buf.slice(0, i).trim()
        buf = buf.slice(i + 1)
        if (!line) continue
        try { frames.push(JSON.parse(line)) } catch { frames.push({ __parse_error: line }) }
      }
    })
    setTimeout(() => { p.kill("SIGKILL"); resolve(frames) }, ms)
  })
}

// Spawn the engine expecting it to exit on its own; capture code + stderr.
// A process killed by a signal (code === null, empty stderr) is a spawn race
// while the runner is loaded with other concurrent test files — not a contract
// failure — so retry a couple of times before reporting.
async function runExpectExit(args) {
  for (let attempt = 0; ; attempt++) {
    const r = await new Promise((resolve) => {
      const p = spawn(BIN, args, { stdio: ["ignore", "pipe", "pipe"] })
      let err = ""
      p.stderr.on("data", (d) => { err += d.toString() })
      p.on("exit", (code, signal) => resolve({ code, signal, err }))
    })
    if (r.code !== null || attempt >= 2) return r
  }
}

test("engine binary is present (built)", { skip: !HAVE_BIN && "run ./build.sh first" }, () => {
  assert.ok(HAVE_BIN, "bin/omaviz-engine must exist")
})

test("emits well-formed frames with the documented contract", { skip: !HAVE_BIN }, async () => {
  const frames = await collect(["--source", "gen=sweep", "--bands", "16"], 900)
  assert.ok(frames.length > 20, `expected many frames, got ${frames.length}`)
  for (const f of frames) {
    assert.ok(!f.__parse_error, `unparseable line: ${f.__parse_error}`)
    assert.ok(Array.isArray(f.bands), "bands must be an array")
    assert.equal(f.bands.length, 16, "band count must equal --bands")
    assert.equal(typeof f.energy, "number")
    assert.equal(typeof f.beat, "number")
    assert.equal(typeof f.silent, "boolean")
    assert.equal(f.source, "gen")
    assert.ok(f.t > 0, "frame must carry an emission timestamp")
    for (const b of f.bands) assert.ok(b >= 0 && b <= 1, `band out of range: ${b}`)
  }
})

test("emits at ~60 Hz (raw feed, no decimation)", { skip: !HAVE_BIN }, async () => {
  const ms = 1000
  const frames = await collect(["--source", "gen=tone", "--bands", "8"], ms)
  const fps = frames.length / (ms / 1000)
  // Generous band: CI machines vary, but it must clearly be the fast path
  // (not the 5 Hz silence heartbeat).
  assert.ok(fps > 30, `expected ~60 Hz feed, saw ${fps.toFixed(1)} fps`)
})

test("spectrum tracks live audio (the sweep peak actually moves)", { skip: !HAVE_BIN }, async () => {
  // A fast sweep (3 Hz LFO) traverses the band range within the window. If
  // the peak band index never moves, the feed is frozen.
  // (Raw-vs-smoothed output is proven exactly by the Rust unit test
  // `bands_are_raw_no_decay_between_frames`; this test proves the live path.)
  const frames = await collect(["--source", "gen=sweep:rate=3.0", "--bands", "24"], 1500)
  assert.ok(frames.length > 20, "expected live frames")
  const peakIdx = frames.map((f) => f.bands.indexOf(Math.max(...f.bands)))
  const spread = Math.max(...peakIdx) - Math.min(...peakIdx)
  assert.ok(spread >= 4, `spectral peak must traverse bands, spread=${spread}`)
})

test("a quiet signal is NOT flagged silent (faint audio stays visible)", { skip: !HAVE_BIN }, async () => {
  // gen=tone at a low amplitude is audible but quiet: it must not be
  // reported as silent, or the UI would hide faint passages.
  const frames = await collect(["--source", "gen=tone:amp=0.02", "--bands", "16"], 700)
  const visible = frames.filter((f) => !f.silent)
  assert.ok(visible.length > 0, "a quiet-but-audible tone must not be flagged silent")
  assert.ok(visible.some((f) => Math.max(...f.bands) > 0.02), "faint tone must produce visible bands")
})

test("rejects the removed --fall-mode flag", { skip: !HAVE_BIN }, async () => {
  const r = await new Promise((resolve) => {
    const p = spawn(BIN, ["--fall-mode", "linear"], { stdio: ["ignore", "pipe", "pipe"] })
    let err = ""
    p.stderr.on("data", (d) => { err += d.toString() })
    p.on("exit", (code) => resolve({ code, err }))
  })
  assert.notEqual(r.code, 0, "must exit non-zero")
  assert.match(r.err + "", /--fall-mode|unexpected argument/i)
})

test("rejects an out-of-range band count", { skip: !HAVE_BIN }, async () => {
  const r = await runExpectExit(["--source", "gen", "--bands", "0"])
  assert.notEqual(r.code, 0, `expected non-zero exit, got ${r.code}`)
  assert.match(r.err + "", /--bands/)
})
