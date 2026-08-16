//! Shared DSP: windowed FFT -> log-spaced bands -> smoothed envelope + beat.

use realfft::{RealFftPlanner, RealToComplex, num_complex::Complex32};
use std::sync::Arc;

pub const FFT_SIZE: usize = 2048;

pub struct Analyzer {
    fft: Arc<dyn RealToComplex<f32>>,
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
    sample_rate: f32,
}

impl Analyzer {
    pub fn new(sample_rate: f32, n_bands: usize) -> Self {
        let mut planner = RealFftPlanner::<f32>::new();
        let fft = planner.plan_fft_forward(FFT_SIZE);
        let window = (0..FFT_SIZE)
            .map(|i| {
                let x = i as f32 / (FFT_SIZE - 1) as f32;
                0.5 - 0.5 * (std::f32::consts::TAU * x).cos() // Hann
            })
            .collect();

        // Log-spaced band edges between 30 Hz and 16 kHz.
        let bin_hz = sample_rate / FFT_SIZE as f32;
        let (f_lo, f_hi) = (30.0f32, 16_000.0f32.min(sample_rate / 2.0 - bin_hz));
        let mut band_edges = Vec::with_capacity(n_bands);
        let mut prev = (f_lo / bin_hz).floor().max(1.0) as usize;
        for b in 0..n_bands {
            let t = (b + 1) as f32 / n_bands as f32;
            let f = f_lo * (f_hi / f_lo).powf(t);
            let mut hi = (f / bin_hz).round() as usize;
            hi = hi.min(FFT_SIZE / 2);
            if hi <= prev {
                hi = prev + 1;
            }
            band_edges.push((prev, hi.min(FFT_SIZE / 2)));
            prev = hi;
        }

        Self {
            spectrum: fft.make_output_vec(),
            scratch_in: vec![0.0; FFT_SIZE],
            fft,
            window,
            ring: vec![0.0; FFT_SIZE],
            band_edges,
            bands: vec![0.0; n_bands],
            energy: 0.0,
            beat: 0.0,
            energy_avg: 0.0,
            attack: 0.55,
            decay: 0.12,
            sample_rate,
        }
    }

    pub fn sample_rate(&self) -> f32 {
        self.sample_rate
    }

    /// Push interleaved-mixed mono samples; keeps the newest FFT_SIZE.
    pub fn push(&mut self, samples: &[f32]) {
        if samples.len() >= FFT_SIZE {
            self.ring
                .copy_from_slice(&samples[samples.len() - FFT_SIZE..]);
        } else {
            let keep = FFT_SIZE - samples.len();
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

        let norm = 2.0 / FFT_SIZE as f32;
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
            let k = if v > prev { self.attack } else { self.decay };
            self.bands[i] = prev + (v - prev) * k;
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
        let a = Analyzer::new(48_000.0, 24);
        assert_eq!(a.bands.len(), 24);
        assert_eq!(a.bands, vec![0.0; 24]);
        assert_eq!(a.sample_rate(), 48_000.0);
    }

    #[test]
    fn silence_produces_zero_energy() {
        let mut a = Analyzer::new(48_000.0, 16);
        a.push(&vec![0.0; FFT_SIZE]);
        a.analyze();
        assert_eq!(a.energy, 0.0);
        assert!(a.is_silent(), "all-zero input must be silent");
    }

    #[test]
    fn loud_tone_produces_nonzero_energy_and_is_not_silent() {
        let mut a = Analyzer::new(48_000.0, 16);
        // 1 kHz sine at full amplitude.
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
        let mut a = Analyzer::new(48_000.0, 8);
        // Two short pushes that together cover less than FFT_SIZE.
        let chunk: Vec<f32> = (0..512).map(|i| (i as f32 * 0.01).sin()).collect();
        a.push(&chunk);
        a.push(&chunk);
        a.analyze();
        // Should not panic and bands should remain finite.
        for b in &a.bands {
            assert!(b.is_finite());
        }
    }
}
