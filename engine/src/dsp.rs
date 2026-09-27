//! Shared DSP: windowed FFT -> log-spaced bands.
//!
//! v8.4: the engine emits RAW band magnitudes. All visual physics (attack,
//! release, peak caps, sustain) lives in the renderer (Physics.js) so every
//! surface shares ONE motion model and the engine stays a pure analyzer.
//! Removed here: attack/decay smoothing and the `linear_fall` mode — those
//! shaped the data stream, which meant two surfaces fed at different rates
//! behaved differently.

use realfft::{RealFftPlanner, RealToComplex, num_complex::Complex32};
use std::sync::Arc;

#[allow(dead_code)]
pub const FFT_SIZE: usize = 2048;

/// Bands at or below this magnitude are treated as "no signal" for the
/// silent flag / heartbeat optimisation. Well below any audible content.
const SILENCE_FLOOR: f32 = 0.02;

#[derive(Debug, Clone)]
pub struct AudioChunk {
    pub samples: Vec<f32>,
    pub rate: u32,
}

pub struct Analyzer {
    fft: Arc<dyn RealToComplex<f32>>,
    fft_size: usize,
    window: Vec<f32>,
    ring: Vec<f32>,
    scratch_in: Vec<f32>,
    spectrum: Vec<Complex32>,
    band_edges: Vec<(usize, usize)>,
    pub bands: Vec<f32>,
    pub energy: f32,
    pub beat: f32,
    energy_avg: f32,
    sample_rate: f32,
}

impl Analyzer {
    pub fn new(sample_rate: f32, n_bands: usize, fft_size: usize) -> Self {
        let mut planner = RealFftPlanner::<f32>::new();
        let fft = planner.plan_fft_forward(fft_size);
        let window = (0..fft_size)
            .map(|i| {
                let x = i as f32 / (fft_size - 1) as f32;
                0.5 - 0.5 * (std::f32::consts::TAU * x).cos() // Hann
            })
            .collect();

        // Log-spaced band edges between 30 Hz and 16 kHz.
        let bin_hz = sample_rate / fft_size as f32;
        let (f_lo, f_hi) = (30.0f32, 16_000.0f32.min(sample_rate / 2.0 - bin_hz));
        let mut band_edges = Vec::with_capacity(n_bands);
        let mut prev = (f_lo / bin_hz).floor().max(1.0) as usize;
        for b in 0..n_bands {
            let t = (b + 1) as f32 / n_bands as f32;
            let f = f_lo * (f_hi / f_lo).powf(t);
            let mut hi = (f / bin_hz).round() as usize;
            hi = hi.min(fft_size / 2);
            if hi <= prev {
                hi = prev + 1;
            }
            band_edges.push((prev, hi.min(fft_size / 2)));
            prev = hi;
        }

        Self {
            spectrum: fft.make_output_vec(),
            scratch_in: vec![0.0; fft_size],
            fft,
            fft_size,
            window,
            ring: vec![0.0; fft_size],
            band_edges,
            bands: vec![0.0; n_bands],
            energy: 0.0,
            beat: 0.0,
            energy_avg: 0.0,
            sample_rate,
        }
    }

    pub fn sample_rate(&self) -> f32 {
        self.sample_rate
    }

    /// Downsampled time-domain snippet (newest last) for the oscilloscope.
    pub fn wave_snippet(&self, n: usize) -> Vec<f32> {
        let len = self.ring.len();
        if n == 0 || len == 0 {
            return vec![];
        }
        (0..n)
            .map(|i| {
                let idx = (i * len / n).min(len - 1);
                self.ring[idx].clamp(-1.0, 1.0)
            })
            .collect()
    }

    /// Push interleaved-mixed mono samples; keeps the newest fft_size.
    pub fn push(&mut self, samples: &[f32]) {
        let n = self.fft_size;
        if samples.len() >= n {
            self.ring
                .copy_from_slice(&samples[samples.len() - n..]);
        } else {
            let keep = n - samples.len();
            self.ring.copy_within(samples.len().., 0);
            self.ring[keep..].copy_from_slice(samples);
        }
    }

    /// Recompute bands from the current ring. Cheap enough for 60 Hz.
    /// RAW output: no smoothing/attack/decay — the renderer owns motion.
    pub fn analyze(&mut self) {
        for (d, (s, w)) in self
            .scratch_in
            .iter_mut()
            .zip(self.ring.iter().zip(self.window.iter()))
        {
            *d = s * w;
        }
        if self
            .fft
            .process(&mut self.scratch_in, &mut self.spectrum)
            .is_err()
        {
            return;
        }

        let norm = 2.0 / self.fft_size as f32;
        let mut total = 0.0;
        for (i, &(lo, hi)) in self.band_edges.iter().enumerate() {
            let mut peak = 0.0f32;
            for c in &self.spectrum[lo..hi.max(lo + 1)] {
                peak = peak.max(c.norm() * norm);
            }
            // dB scale -> 0..1. Quiet-but-audible bands keep a visible value
            // (~-60 dB => 0.14), so faint passages still render.
            let db = 20.0 * (peak + 1e-9).log10();
            let v = ((db + 70.0) / 70.0).clamp(0.0, 1.0);
            self.bands[i] = v;
            total += v;
        }
        self.energy = total / self.bands.len() as f32;

        // Simple onset: energy above running average.
        self.energy_avg += (self.energy - self.energy_avg) * 0.05;
        let excess = (self.energy - self.energy_avg * 1.35).max(0.0);
        self.beat = (self.beat * 0.85).max((excess * 6.0).min(1.0));
    }

    /// True only when NO band carries audible content. Mean energy is not
    /// enough: a bass-only passage has many near-zero bands but one loud
    /// band, and must not be flagged silent (that hid faint passages).
    pub fn is_silent(&self) -> bool {
        !self.bands.iter().any(|&b| b > SILENCE_FLOOR)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn new_allocates_requested_band_count() {
        let a = Analyzer::new(48_000.0, 24, FFT_SIZE);
        assert_eq!(a.bands.len(), 24);
        assert_eq!(a.bands, vec![0.0; 24]);
        assert_eq!(a.sample_rate(), 48_000.0);
    }

    #[test]
    fn silence_produces_zero_energy() {
        let mut a = Analyzer::new(48_000.0, 16, FFT_SIZE);
        a.push(&vec![0.0; FFT_SIZE]);
        a.analyze();
        assert_eq!(a.energy, 0.0);
        assert!(a.is_silent(), "all-zero input must be silent");
    }

    #[test]
    fn loud_tone_produces_nonzero_energy_and_is_not_silent() {
        let mut a = Analyzer::new(48_000.0, 16, FFT_SIZE);
        let sr = 48_000.0;
        let samples: Vec<f32> = (0..FFT_SIZE)
            .map(|i| (2.0 * std::f32::consts::PI * 1000.0 * i as f32 / sr).sin() * 0.5)
            .collect();
        a.push(&samples);
        a.analyze();
        assert!(a.energy > 0.0, "a tone should produce energy");
        assert!(!a.is_silent(), "a loud tone is not silent");
    }

    /// The heart of the "faint audio invisible" fix: a quietly audible band
    /// must survive AND must not be reported as silence.
    #[test]
    fn faint_tone_is_visible_and_not_silent() {
        let mut a = Analyzer::new(48_000.0, 32, FFT_SIZE);
        let sr = 48_000.0;
        // ~-46 dBFS tone: clearly audible, far below "loud".
        let samples: Vec<f32> = (0..FFT_SIZE)
            .map(|i| (2.0 * std::f32::consts::PI * 440.0 * i as f32 / sr).sin() * 0.005)
            .collect();
        a.push(&samples);
        a.analyze();
        let loudest = a.bands.iter().cloned().fold(0.0f32, f32::max);
        assert!(loudest > SILENCE_FLOOR, "faint tone must exceed the floor, got {loudest}");
        assert!(!a.is_silent(), "a faint but audible tone must NOT be silent");
    }

    /// Bands are raw: a loud frame followed by a silent frame must NOT be
    /// smoothed — the renderer does the release.
    #[test]
    fn bands_are_raw_no_decay_between_frames() {
        let mut a = Analyzer::new(48_000.0, 8, FFT_SIZE);
        let sr = 48_000.0;
        let loud: Vec<f32> = (0..FFT_SIZE)
            .map(|i| (2.0 * std::f32::consts::PI * 1000.0 * i as f32 / sr).sin() * 0.5)
            .collect();
        a.push(&loud);
        a.analyze();
        assert!(a.bands.iter().any(|&v| v > 0.0));
        // Immediately silent: raw bands must drop to ~0 in ONE frame.
        a.push(&vec![0.0; FFT_SIZE]);
        a.analyze();
        assert!(a.bands.iter().all(|&v| v == 0.0), "raw output must not decay smoothly");
    }

    #[test]
    fn push_handles_short_buffers_with_ring() {
        let mut a = Analyzer::new(48_000.0, 8, FFT_SIZE);
        let chunk: Vec<f32> = (0..512).map(|i| (i as f32 * 0.01).sin()).collect();
        a.push(&chunk);
        a.push(&chunk);
        a.analyze();
        for b in &a.bands {
            assert!(b.is_finite());
        }
    }

    #[test]
    fn fft_1024_analyzes_and_stays_finite() {
        let mut a = Analyzer::new(48_000.0, 16, 1024);
        let chunk: Vec<f32> = (0..512).map(|i| (i as f32 * 0.01).sin()).collect();
        a.push(&chunk);
        a.analyze();
        assert_eq!(a.bands.len(), 16);
        for b in &a.bands {
            assert!(b.is_finite());
        }
    }

    #[test]
    fn wave_snippet_downsamples_ring() {
        let mut a = Analyzer::new(48_000.0, 8, FFT_SIZE);
        a.push(&vec![0.25; FFT_SIZE]);
        let w = a.wave_snippet(128);
        assert_eq!(w.len(), 128);
        assert!(w.iter().all(|&v| (v - 0.25).abs() < 1e-6));
    }
}
