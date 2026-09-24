//! Shared DSP: windowed FFT -> log-spaced bands -> smoothed envelope + beat.
//! Ported verbatim from v6/daemon/src/dsp.rs (backend-agnostic: consumes f32 mono).

use realfft::{RealFftPlanner, RealToComplex, num_complex::Complex32};
use std::sync::Arc;

#[allow(dead_code)]
pub const FFT_SIZE: usize = 2048;

#[derive(Debug, Clone)]
pub struct AudioChunk {
    pub samples: Vec<f32>,
    pub rate: u32,
    pub channels: u16,
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
    attack: f32,
    decay: f32,
    linear_fall: bool,
    sample_rate: f32,
}

impl Analyzer {
    pub fn new(sample_rate: f32, n_bands: usize, fft_size: usize, linear_fall: bool) -> Self {
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
            attack: 0.70,
            decay: 0.12,
            linear_fall,
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
            // dB scale -> 0..1
            let db = 20.0 * (peak + 1e-9).log10();
            let v = ((db + 70.0) / 70.0).clamp(0.0, 1.0);
            let prev = self.bands[i];
            self.bands[i] = if self.linear_fall {
                // Winamp-style: instant rise, fixed-rate linear fall.
                if v > prev { v } else { (prev - 0.05).max(v) }
            } else {
                let k = if v > prev { self.attack } else { self.decay };
                prev + (v - prev) * k
            };
            total += self.bands[i];
        }
        self.energy = total / self.bands.len() as f32;

        // Simple onset: energy above running average.
        self.energy_avg += (self.energy - self.energy_avg) * 0.05;
        let excess = (self.energy - self.energy_avg * 1.35).max(0.0);
        self.beat = (self.beat * 0.85).max((excess * 6.0).min(1.0));
    }

    pub fn is_silent(&self) -> bool {
        self.energy < 0.02
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn new_allocates_requested_band_count() {
        let a = Analyzer::new(48_000.0, 24, FFT_SIZE, false);
        assert_eq!(a.bands.len(), 24);
        assert_eq!(a.bands, vec![0.0; 24]);
        assert_eq!(a.sample_rate(), 48_000.0);
    }

    #[test]
    fn silence_produces_zero_energy() {
        let mut a = Analyzer::new(48_000.0, 16, FFT_SIZE, false);
        a.push(&vec![0.0; FFT_SIZE]);
        a.analyze();
        assert_eq!(a.energy, 0.0);
        assert!(a.is_silent(), "all-zero input must be silent");
    }

    #[test]
    fn loud_tone_produces_nonzero_energy_and_is_not_silent() {
        let mut a = Analyzer::new(48_000.0, 16, FFT_SIZE, false);
        let sr = 48_000.0;
        let samples: Vec<f32> = (0..FFT_SIZE)
            .map(|i| (2.0 * std::f32::consts::PI * 1000.0 * i as f32 / sr).sin() * 0.5)
            .collect();
        a.push(&samples);
        a.analyze();
        assert!(a.energy > 0.0, "a tone should produce energy");
        assert!(!a.is_silent(), "a loud tone is not silent");
    }

    #[test]
    fn push_handles_short_buffers_with_ring() {
        let mut a = Analyzer::new(48_000.0, 8, FFT_SIZE, false);
        let chunk: Vec<f32> = (0..512).map(|i| (i as f32 * 0.01).sin()).collect();
        a.push(&chunk);
        a.push(&chunk);
        a.analyze();
        for b in &a.bands {
            assert!(b.is_finite());
        }
    }

    #[test]
    fn linear_fall_rises_instantly_and_falls_linearly() {
        let mut a = Analyzer::new(48_000.0, 8, FFT_SIZE, true);
        let sr = 48_000.0;
        let loud: Vec<f32> = (0..FFT_SIZE)
            .map(|i| (2.0 * std::f32::consts::PI * 1000.0 * i as f32 / sr).sin() * 0.5)
            .collect();
        a.push(&loud);
        a.analyze();
        let hot: Vec<f32> = a.bands.clone();
        assert!(hot.iter().any(|&v| v > 0.0), "linear mode must rise instantly");
        // Silence: linear mode must fall by exactly the fixed step per frame.
        a.push(&vec![0.0; FFT_SIZE]);
        a.analyze();
        for (h, b) in hot.iter().zip(a.bands.iter()) {
            let expected = (*h - 0.05).max(0.0);
            assert!((b - expected).abs() < 1e-5, "linear fall step wrong: {b} vs {expected}");
        }
    }

    #[test]
    fn fft_1024_analyzes_and_stays_finite() {
        let mut a = Analyzer::new(48_000.0, 16, 1024, false);
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
        let mut a = Analyzer::new(48_000.0, 8, FFT_SIZE, false);
        a.push(&vec![0.25; FFT_SIZE]);
        let w = a.wave_snippet(128);
        assert_eq!(w.len(), 128);
        assert!(w.iter().all(|&v| (v - 0.25).abs() < 1e-6));
    }
}
