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
    pub channels: usize,
}

pub struct Analyzer {
    fft: Arc<dyn RealToComplex<f32>>,
    fft_size: usize,
    window: Vec<f32>,
    ring: Vec<f32>,
    channel_rings: Vec<Vec<f32>>,
    power: Vec<f32>,
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
            // More output bands than FFT bins must safely share the final bin.
            let lo = prev.min(fft_size / 2);
            band_edges.push((lo, hi.min(fft_size / 2 + 1).max(lo + 1)));
            prev = hi;
        }

        Self {
            spectrum: fft.make_output_vec(),
            scratch_in: vec![0.0; fft_size],
            fft,
            fft_size,
            window,
            ring: vec![0.0; fft_size],
            channel_rings: Vec::new(),
            power: vec![0.0; fft_size / 2 + 1],
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

    /// Whole-window loudness for Siri. Measuring the decimated oscilloscope
    /// snippet aliases tones whose period coincides with its sample stride.
    pub fn rms_level(&self) -> f32 {
        if !self.channel_rings.is_empty() {
            let sum: f32 = self.channel_rings.iter().flatten().map(|v| v*v).sum();
            return (sum / (self.fft_size * self.channel_rings.len()) as f32).sqrt();
        }
        (self.ring.iter().map(|v| v*v).sum::<f32>() / self.ring.len().max(1) as f32).sqrt()
    }

    /// Six independent RMS controls from the FFT already used by the spectrum.
    /// Parseval scaling compensates Hann window power; no second FFT or smoothing.
    pub fn siri_levels(&self) -> [f32; 6] {
        let mut power = [0.0_f32; 6];
        let edges = [180.0, 450.0, 1000.0, 2500.0, 6000.0];
        let mut band = 0;
        for (i, c) in self.spectrum.iter().enumerate() {
            let hz = i as f32 * self.sample_rate / self.fft_size as f32;
            while band < edges.len() && hz >= edges[band] { band += 1; }
            let p = c.norm_sqr();
            if p.is_finite() {
                let weight = if i == 0 || i == self.fft_size / 2 { 1.0 } else { 2.0 };
                power[band] += p * weight;
            }
        }
        let window_power: f32 = self.window.iter().map(|v| v*v).sum();
        power.map(|p| (p / (self.fft_size as f32 * window_power)).sqrt().clamp(0.0, 1.0))
    }

    /// Peak-preserving display envelope: ordered min/max pairs per bucket.
    /// Unlike point decimation, a narrow transient or high tone cannot vanish
    /// between display samples. This is a waveform envelope, not a frequency plot.
    pub fn wave_snippet(&self, n: usize) -> Vec<f32> {
        let len = self.ring.len();
        if n == 0 || len == 0 { return vec![]; }
        if n >= len { return self.ring.clone(); }
        if n == 1 { return vec![self.ring.iter().copied().max_by(|a,b| a.abs().total_cmp(&b.abs())).unwrap_or(0.0)]; }
        let buckets = n / 2;
        let mut out = Vec::with_capacity(n);
        for bucket in 0..buckets {
            let start = bucket * len / buckets;
            let end = (bucket + 1) * len / buckets;
            let mut lo = start; let mut hi = start;
            for i in start+1..end {
                if self.ring[i] < self.ring[lo] { lo = i; }
                if self.ring[i] > self.ring[hi] { hi = i; }
            }
            let (first, second) = if lo <= hi { (lo,hi) } else { (hi,lo) };
            out.push(self.ring[first]); out.push(self.ring[second]);
        }
        if n % 2 != 0 { out.push(self.ring[len-1]); }
        out
    }

    /// Mono input stays on the single-FFT fast path.
    pub fn push(&mut self, samples: &[f32]) {
        self.channel_rings.clear();
        push_ring(&mut self.ring, samples.iter().copied(), samples.len());
    }

    pub fn push_interleaved(&mut self, samples: &[f32], channels: usize) {
        if channels <= 1 { self.push(samples); return; }
        if self.channel_rings.len() != channels {
            self.channel_rings = vec![vec![0.0; self.fft_size]; channels];
        }
        let frames = samples.len() / channels;
        for (c, ring) in self.channel_rings.iter_mut().enumerate() {
            push_ring(ring, samples.chunks_exact(channels).map(|frame| frame[c]), frames);
        }
        // A real channel is a meaningful audio trace; arithmetic downmixing
        // would erase antiphase content. Choose the strongest whole window.
        let strongest = self.channel_rings.iter().max_by(|a,b| {
            let energy = |r: &Vec<f32>| r.iter().map(|v| v*v).sum::<f32>();
            energy(a).total_cmp(&energy(b))
        }).unwrap();
        self.ring.copy_from_slice(strongest);
    }

    /// Recompute bands from the current ring. Cheap enough for 60 Hz.
    /// RAW output: no smoothing/attack/decay — the renderer owns motion.
    pub fn analyze(&mut self) {
        self.power.fill(0.0);
        let channels = self.channel_rings.len().max(1);
        for channel in 0..channels {
            let ring = if self.channel_rings.is_empty() { &self.ring } else { &self.channel_rings[channel] };
            for (d, (s, w)) in self.scratch_in.iter_mut().zip(ring.iter().zip(&self.window)) { *d = s * w; }
            if self.fft.process(&mut self.scratch_in, &mut self.spectrum).is_err() { return; }
            for (power, bin) in self.power.iter_mut().zip(&self.spectrum) { *power += bin.norm_sqr() / channels as f32; }
        }
        // Consumers use magnitudes, including Siri's Parseval envelopes.
        for (bin, power) in self.spectrum.iter_mut().zip(&self.power) { *bin = Complex32::new(power.sqrt(), 0.0); }

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

fn push_ring(ring: &mut [f32], samples: impl Iterator<Item=f32>, count: usize) {
    let keep = ring.len().saturating_sub(count);
    if keep > 0 { ring.copy_within(count.., 0); }
    let skip = count.saturating_sub(ring.len());
    for (out, sample) in ring[keep..].iter_mut().zip(samples.skip(skip)) {
        *out = if sample.is_finite() { sample.clamp(-1.0,1.0) } else { 0.0 };
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stereo_energy_survives_opposite_phase_and_one_sided_audio() {
        let tone: Vec<f32> = (0..2048).map(|i| (std::f32::consts::TAU*440.0*i as f32/48000.0).sin()*0.5).collect();
        let mut mono = Analyzer::new(48000.0,128,2048); mono.push(&tone); mono.analyze();
        for polarity in [1.0_f32, -1.0, 0.0] {
            let stereo: Vec<f32> = tone.iter().flat_map(|v| [*v,*v*polarity]).collect();
            let mut a = Analyzer::new(48000.0,128,2048); a.push_interleaved(&stereo,2); a.analyze();
            assert!(!a.is_silent());
            assert!((a.rms_level()-mono.rms_level()*((1.0+polarity*polarity)/2.0).sqrt()).abs()<0.0001);
            assert!(a.wave_snippet(128).iter().any(|v| v.abs()>0.4));
            if polarity != 0.0 {
                for (actual,expected) in a.bands.iter().zip(&mono.bands) { assert!((actual-expected).abs()<0.0001); }
            }
        }
    }

    #[test]
    fn supported_fft_and_band_extremes_do_not_panic() {
        for size in [256, 512, 1024, 2048, 8192] {
            for count in [4, 32, 128, 256, 512] {
                let mut analyzer = Analyzer::new(48000.0, count, size);
                analyzer.push(&vec![0.0; size]);
                analyzer.analyze();
                assert_eq!(analyzer.bands.len(), count);
                assert!(analyzer.bands.iter().all(|v| v.is_finite()));
            }
        }
    }

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
    fn invalid_pcm_is_sanitized_before_fft_and_waveform() {
        let mut a = Analyzer::new(48_000.0, 32, FFT_SIZE);
        a.push(&[f32::NAN, f32::INFINITY, f32::NEG_INFINITY, 5.0, -5.0]);
        a.analyze();
        assert!(a.bands.iter().all(|v| v.is_finite()));
        assert!(a.wave_snippet(FFT_SIZE).iter().all(|v| v.is_finite() && v.abs() <= 1.0));
        assert!(a.energy.is_finite() && a.beat.is_finite());
        a.push(&vec![0.0; FFT_SIZE]);
        a.analyze();
        assert!(a.is_silent());
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
    fn waveform_preserves_tones_at_the_old_display_sample_stride() {
        let mut a = Analyzer::new(48_000.0, 32, FFT_SIZE);
        for hz in [3000.0_f32, 6000.0, 12000.0] {
            let samples: Vec<f32> = (0..FFT_SIZE).map(|i|
                0.5 * (std::f32::consts::TAU * hz * i as f32 / 48_000.0).sin()).collect();
            a.push(&samples);
            let display = a.wave_snippet(128);
            let aliased = (display.iter().map(|v| v*v).sum::<f32>() / 128.0).sqrt();
            assert!(aliased > 0.3, "display envelope must retain audible tones");
            assert!((a.rms_level() - 0.5/std::f32::consts::SQRT_2).abs() < 0.001);
        }
    }

    #[test]
    fn siri_layers_separate_equal_loudness_tones_and_conserve_power() {
        for rate in [44100.0, 48000.0] {
            let mut a = Analyzer::new(rate, 32, FFT_SIZE);
            for (band, hz) in [93.75, 300.0, 703.125, 1500.0, 3750.0, 9000.0].iter().enumerate() {
                let samples: Vec<f32> = (0..FFT_SIZE).map(|i|
                    0.2 * (std::f32::consts::TAU * hz * i as f32 / rate).sin()).collect();
                a.push(&samples); a.analyze();
                let levels = a.siri_levels();
                let rms = a.rms_level();
                assert!((levels[band] - rms).abs() < 0.004, "dominant band {band}: {levels:?}");
                assert!(levels.iter().enumerate().all(|(i,v)| i == band || *v < 0.004));
                assert!((levels.iter().map(|v|v*v).sum::<f32>().sqrt() - rms).abs() < 0.004);
            }
            a.push(&vec![0.0; FFT_SIZE]); a.analyze();
            assert_eq!(a.siri_levels(), [0.0; 6]);
        }
    }

    #[test]
    fn siri_loudness_preserves_quiet_levels_and_silence() {
        let mut a = Analyzer::new(48_000.0, 32, FFT_SIZE);
        for level in [0.0_f32, 0.0001, 0.002, 0.07, 1.0] {
            a.push(&vec![level; FFT_SIZE]);
            assert!((a.rms_level()-level).abs() < 0.00001);
        }
        a.push(&vec![f32::NAN; FFT_SIZE]);
        assert_eq!(a.rms_level(), 0.0);
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
