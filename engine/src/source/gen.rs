//! Deterministic synthetic audio generator backend (engine lane #11).
//!
//! Produces a structured, time-varying mono signal so the FFT analyzer yields a
//! moving spectrum — ideal for driving the visuals (bars/wave/fire) without real
//! audio. Fully deterministic (no RNG): the same `--source gen=...` invocation
//! always produces the same waveform, which the screenshot harness relies on
//! for reproducible captures.
//!
//! CLI grammar (the text after the `gen` prefix, e.g. `--source gen=tone:freq=1000`):
//!   gen                              -> Mixed (default)
//!   gen=tone[:freq=440]              -> steady sine at `freq` Hz
//!   gen=noise                        -> deterministic pseudo-noise (incommensurate sines)
//!   gen=sweep[:rate=0.2][:min=80][:max=7080] -> 80..7080 Hz sine sweep, `rate` Hz LFO
//!   gen=mixed[:pulse=1.5][:low=120] -> multi-partial w/ pulsing low partial (beat/Wave)

use crate::dsp::AudioChunk;
use crate::source::SourceEvent;
use anyhow::{bail, Result};
use std::f32::consts::PI;
use std::sync::mpsc::Sender;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GenMode {
    Mixed,
    Tone,
    Sweep,
    Noise,
}

#[derive(Debug, Clone)]
pub struct GenParams {
    pub tone_freq: f32,
    pub sweep_rate: f32,
    pub sweep_min: f32,
    pub sweep_max: f32,
    pub mixed_pulse: f32,
    pub mixed_low: f32,
}

impl Default for GenParams {
    fn default() -> Self {
        Self {
            tone_freq: 440.0,
            sweep_rate: 0.2,
            sweep_min: 80.0,
            sweep_max: 7080.0,
            mixed_pulse: 1.5,
            mixed_low: 120.0,
        }
    }
}

/// Parse a `gen` spec (text after the `gen` prefix) into a mode + params.
pub fn parse_spec(spec: &str) -> Result<(GenMode, GenParams)> {
    let spec = spec.strip_prefix('=').unwrap_or(spec);
    let (mode_str, rest) = match spec.split_once(':') {
        Some((m, r)) => (m, r),
        None => (spec, ""),
    };
    let mode = match mode_str {
        "" | "mixed" | "mix" => GenMode::Mixed,
        "tone" | "sin" | "sine" => GenMode::Tone,
        "noise" | "pink" => GenMode::Noise,
        "sweep" | "chirp" => GenMode::Sweep,
        other => bail!("unknown gen mode: {other} (use tone|noise|sweep|mixed)"),
    };
    let mut params = GenParams::default();
    for kv in rest.split(|c| c == ':' || c == ';') {
        if kv.is_empty() {
            continue;
        }
        if let Some((k, v)) = kv.split_once('=') {
            match k {
                "freq" => params.tone_freq = v.parse().unwrap_or(params.tone_freq),
                "rate" => params.sweep_rate = v.parse().unwrap_or(params.sweep_rate),
                "min" => params.sweep_min = v.parse().unwrap_or(params.sweep_min),
                "max" => params.sweep_max = v.parse().unwrap_or(params.sweep_max),
                "pulse" => params.mixed_pulse = v.parse().unwrap_or(params.mixed_pulse),
                "low" => params.mixed_low = v.parse().unwrap_or(params.mixed_low),
                _ => {}
            }
        }
    }
    Ok((mode, params))
}

/// Spawn the generator thread. Returns once the thread is launched.
pub fn spawn(spec: &str, tx: Sender<SourceEvent>) -> Result<()> {
    let (mode, params) = parse_spec(spec)?;
    std::thread::spawn(move || run(tx, mode, params));
    Ok(())
}

const RATE: u32 = 48_000;
const CHUNK: usize = 800; // ~16.6 ms at 48 kHz; loops at ~60 Hz

fn run(tx: Sender<SourceEvent>, mode: GenMode, params: GenParams) {
    let mut t = 0.0f32;
    let dt = 1.0 / RATE as f32;
    loop {
        let mut samples = Vec::with_capacity(CHUNK);
        for _ in 0..CHUNK {
            samples.push(synth(mode, t, &params));
            t += dt;
        }
        if tx
            .send(SourceEvent::Chunk(AudioChunk { samples, rate: RATE }))
            .is_err()
        {
            break; // consumer gone
        }
        std::thread::sleep(std::time::Duration::from_millis(16));
    }
}

/// Sample the synthetic signal at time `t` (seconds). Deterministic.
pub fn synth(mode: GenMode, t: f32, p: &GenParams) -> f32 {
    match mode {
        GenMode::Noise => {
            // Incommensurate sines -> noise-like but fully deterministic.
            0.3 * (1234.5 * t).sin() + 0.3 * (3456.7 * t).sin() + 0.4 * (5432.1 * t).sin()
        }
        GenMode::Tone => 0.5 * (2.0 * PI * p.tone_freq * t).sin(),
        GenMode::Sweep => {
            let f = p.sweep_min
                + (p.sweep_max - p.sweep_min) * (0.5 + 0.5 * (2.0 * PI * p.sweep_rate * t).sin());
            0.5 * (2.0 * PI * f * t).sin()
        }
        GenMode::Mixed => {
            // Pulsing low partial gives the beat detector and Wave/Fire something
            // to track; higher partials ride slower LFO envelopes.
            let pulse = 0.5 + 0.5 * (2.0 * PI * p.mixed_pulse * t).sin();
            let mut s = 0.4 * pulse * (2.0 * PI * p.mixed_low * t).sin();
            s += 0.20 * (0.5 + 0.5 * (2.0 * PI * 0.3 * t).sin()) * (2.0 * PI * 600.0 * t).sin();
            s += 0.15 * (0.5 + 0.5 * (2.0 * PI * 0.7 * t).sin()) * (2.0 * PI * 1800.0 * t).sin();
            s += 0.12 * (0.5 + 0.5 * (2.0 * PI * 0.5 * t).sin()) * (2.0 * PI * 5000.0 * t).sin();
            s
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::source::SourceEvent;
    use std::sync::mpsc::channel;
    use std::time::Duration;

    #[test]
    fn parse_default_is_mixed() {
        assert_eq!(parse_spec("").unwrap().0, GenMode::Mixed);
        assert_eq!(parse_spec("=mixed").unwrap().0, GenMode::Mixed);
    }

    #[test]
    fn parse_modes() {
        assert_eq!(parse_spec("=tone").unwrap().0, GenMode::Tone);
        assert_eq!(parse_spec("=noise").unwrap().0, GenMode::Noise);
        assert_eq!(parse_spec("=sweep").unwrap().0, GenMode::Sweep);
    }

    #[test]
    fn parse_params_override_defaults() {
        let (_, p) = parse_spec("=tone:freq=1000").unwrap();
        assert_eq!(p.tone_freq, 1000.0);
        let (_, p) = parse_spec("=sweep:rate=2.0:min=200:max=6000").unwrap();
        assert_eq!(p.sweep_rate, 2.0);
        assert_eq!(p.sweep_min, 200.0);
        assert_eq!(p.sweep_max, 6000.0);
    }

    #[test]
    fn parse_unknown_mode_errors() {
        assert!(parse_spec("=bogus").is_err());
    }

    #[test]
    fn synth_is_deterministic() {
        let p = GenParams::default();
        for mode in [GenMode::Mixed, GenMode::Tone, GenMode::Sweep, GenMode::Noise] {
            assert_eq!(synth(mode, 0.123, &p), synth(mode, 0.123, &p));
            assert_eq!(synth(mode, 4.567, &p), synth(mode, 4.567, &p));
        }
    }

    #[test]
    fn mixed_mode_varies_over_time() {
        let p = GenParams::default();
        let a = synth(GenMode::Mixed, 0.0, &p);
        let b = synth(GenMode::Mixed, 0.25, &p);
        assert_ne!(a, b, "mixed signal should move over time");
    }

    #[test]
    fn values_stay_in_range() {
        let p = GenParams::default();
        for i in 0..10_000 {
            let t = i as f32 * 0.013;
            for mode in [GenMode::Mixed, GenMode::Tone, GenMode::Sweep, GenMode::Noise] {
                let v = synth(mode, t, &p);
                assert!(v.is_finite() && v.abs() <= 1.0001, "out of range: {v} ({mode:?})");
            }
        }
    }

    #[test]
    fn spawn_emits_chunk_with_expected_rate_and_length() {
        let (tx, rx) = channel();
        spawn("=tone", tx).unwrap();
        let ev = rx.recv_timeout(Duration::from_secs(3)).expect("should emit a chunk");
        match ev {
            SourceEvent::Chunk(c) => {
                assert_eq!(c.rate, 48_000);
                assert_eq!(c.samples.len(), CHUNK);
            }
            _ => panic!("expected Chunk event"),
        }
    }

    #[test]
    fn spawn_unknown_mode_errors() {
        let (tx, _rx) = channel();
        assert!(spawn("=bogus", tx).is_err());
    }
}
