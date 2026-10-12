"use strict";
const path = require("node:path");
const {test} = require("node:test");
const assert = require("node:assert/strict");
const {spawn} = require("node:child_process");
const BIN = path.join(__dirname, "..", "bin", "omaviz-engine");

// Collect an observable result, not a frame-rate threshold on a shared CI host.
// Every path waits for process close; errors and deadline expiry fail explicitly.
function run(args, count = 0) {
  return new Promise((resolve, reject) => {
    const child = spawn(BIN, args, {stdio: ["ignore", "pipe", "pipe"]});
    let buffer = "", stderr = "", failure = null, complete = false;
    const frames = [];
    const timeout = setTimeout(() => {
      failure = new Error("engine deadline exceeded: " + stderr);
      child.kill("SIGKILL");
    }, 10000);
    child.on("error", error => { clearTimeout(timeout); reject(error); });
    child.stderr.on("data", data => { stderr += data; });
    child.stdout.on("data", data => {
      buffer += data;
      let end;
      while ((end = buffer.indexOf("\n")) >= 0) {
        const line = buffer.slice(0, end); buffer = buffer.slice(end + 1);
        if (!line.trim()) continue;
        try { frames.push(JSON.parse(line)); }
        catch (error) { failure = error; child.kill("SIGKILL"); }
        if (count && frames.length >= count && !complete) {
          complete = true; child.kill("SIGTERM");
        }
      }
    });
    child.on("close", (code, signal) => {
      clearTimeout(timeout);
      if (failure) reject(failure);
      else if (count && !complete) reject(new Error(`engine stopped early (${code}/${signal}): ${stderr}`));
      else resolve({frames, code, stderr});
    });
  });
}

test("generated spectrum respects the wire contract, including extreme supported dimensions", async () => {
  for (const [bands, fft] of [[16, 2048], [512, 256]]) {
    const {frames} = await run(["--source", "gen=tone", "--bands", String(bands), "--fft-size", String(fft)], 12);
    for (const frame of frames) {
      assert.equal(frame.bands.length, bands);
      assert.equal(frame.source, "gen");
      assert.equal(typeof frame.silent, "boolean");
      assert.ok(Number.isFinite(frame.energy) && Number.isFinite(frame.beat));
      assert.ok(frame.t > 0);
      assert.ok(frame.bands.every(value => Number.isFinite(value) && value >= 0 && value <= 1));
    }
  }
});

test("wave mode emits separate finite signed samples", async () => {
  const {frames} = await run(["--source", "gen=tone", "--wave"], 20);
  const wave = frames.find(frame => frame.wave);
  assert.ok(wave && wave.wave.length > 0);
  assert.ok(wave.wave.every(value => Number.isFinite(value) && value >= -1 && value <= 1));
  assert.ok(frames.some(frame => frame.bands));
});

test("quiet audible input remains visible", async () => {
  const {frames} = await run(["--source", "gen=tone:amp=0.02"], 12);
  assert.ok(frames.some(frame => !frame.silent && Math.max(...frame.bands) > 0.02));
});

test("nonfinite PCM cannot corrupt spectrum or waveform JSON", async () => {
  const {frames} = await run(["--source", "gen=tone:amp=NaN", "--wave"], 12);
  assert.ok(frames.some(frame => frame.wave));
  for (const frame of frames) {
    const samples = frame.wave || frame.bands;
    assert.ok(samples.every(value => Number.isFinite(value) && value === 0));
  }
});

test("Siri compact feed keeps metadata and emits finite scalar waveform energy", async () => {
  const {frames} = await run(["--source", "gen=tone", "--bands", "256", "--siri"], 20);
  const spectra = frames.filter(frame => frame.bands);
  const waves = frames.filter(frame => frame.wave);
  assert.ok(spectra.length && waves.length);
  for (const frame of spectra) {
    assert.equal(frame.band_layout, "siri");
    assert.equal(frame.bands.length, 6);
    assert.ok(frame.bands.every(v => Number.isFinite(v) && v >= 0 && v <= 1));
    assert.equal(typeof frame.silent, "boolean");
    assert.ok(Number.isFinite(frame.energy) && Number.isFinite(frame.beat));
    assert.equal(frame.source, "gen");
    assert.ok(frame.t > 0);
  }
  for (const frame of waves) {
    assert.equal(frame.wave.length, 1);
    assert.ok(Number.isInteger(frame.wave_serial) && frame.wave_serial > 0);
    assert.ok(Number.isFinite(frame.wave[0]) && frame.wave[0] >= 0);
  }
  assert.ok(waves.some(frame => frame.wave[0] > 0));
});

test("invalid engine dimensions fail before capture starts", async () => {
  for (const args of [["--bands", "0"], ["--fft-size", "300"]]) {
    const result = await run(["--source", "gen", ...args]);
    assert.notEqual(result.code, null);
    assert.notEqual(result.code, 0);
    assert.match(result.stderr, /must be/);
  }
});
test("Strings feed emits sixteen strand drives while retaining the full waveform", async () => {
  const {frames} = await run(["--source", "gen=tone", "--bands", "256", "--strings"], 20);
  const spectra = frames.filter(frame => frame.bands);
  const waves = frames.filter(frame => frame.wave);
  assert.ok(spectra.length && waves.length);
  for (const frame of spectra) {
    assert.equal(frame.band_layout, "strings");
    assert.equal(frame.bands.length, 16);
    assert.ok(frame.bands.every(v => Number.isFinite(v) && v >= 0 && v <= 1));
    assert.equal(typeof frame.silent, "boolean");
    assert.ok(Number.isFinite(frame.energy) && Number.isFinite(frame.beat) && frame.t > 0);
  }
  for (const frame of waves) assert.equal(frame.wave.length, 128);
});


test("Siri measures high tones that the display waveform undersamples", async () => {
  const {frames} = await run(["--source", "gen=tone:freq=3000", "--siri"], 24);
  const values = frames.filter(frame => frame.wave).map(frame => frame.wave[0]);
  assert.ok(values.length > 0);
  assert.ok(values.slice(-5).every(v => Math.abs(v - 0.5 / Math.sqrt(2)) < 0.01));
});
