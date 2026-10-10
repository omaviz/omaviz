//! omaviz-engine — the single bundled audio engine for the omaviz plugin.
//!
//! Replaces the old (daemon + socket + bridge) topology. It captures from the
//! active audio source, runs the FFT analyzer, and emits one JSON spectrum
//! frame per line on stdout. The Quickshell plugin spawns this binary and
//! parses stdout with Model.parseSpectrumLine — no socket, no systemd, no
//! separate binaries outside the plugin directory.
//!
//! Backend selection is auto by default: `auto`/`""` resolves to PipeWire. Two
//! synthetic backends are compiled in for deterministic offline testing
//! (engine lane #11, no plugin/QML changes):
//!   --source gen[=mode[:param=value;...]]   built-in tone/noise/sweep generator
//!   --source file=<path>[:fps=N][:loop]     replays a recorded spectrum stream
//! The plugin never picks a backend; it just spawns the binary.

mod dsp;
mod frame;
mod source;

use clap::Parser;
use dsp::Analyzer;
use frame::{build_frame, Frame};
use source::SourceEvent;
use std::io::Write;
use std::time::Duration;

#[derive(Parser, Debug)]
#[command(name = "omaviz-engine", about = "omaviz audio capture + spectrum engine")]
struct Cli {
    /// Audio source backend.
    ///   auto|pipewire        capture the default sink monitor (PipeWire)
    ///   gen[=mode[:params]]  built-in generator: tone|noise|sweep|mixed
    ///   file=<path>[:fps=N][:loop]  replay a recorded spectrum stream
    #[arg(long, default_value = "auto")]
    source: String,

    /// Number of spectrum bands in the output frame.
    #[arg(long, default_value_t = 32)]
    bands: usize,

    /// FFT window size in samples (window latency = size/rate, e.g.
    /// 2048 @48kHz ≈ 43ms, 1024 ≈ 21ms). Smaller is snappier but
    /// coarsens bass resolution. Must be a power of two.
    #[arg(long, default_value_t = 2048)]
    fft_size: usize,

    /// Append a 128-point downsampled time-domain snippet ("wave") per
    /// frame for the oscilloscope renderer. Adds ~0.7KB/line.
    #[arg(long, default_value_t = false)]
    wave: bool,

    /// Siri-only compact feed: six spectral RMS layer drives plus full PCM RMS.
    #[arg(long, default_value_t = false)]
    siri: bool,

    /// Strings-only feed: send the exact 16 strand excitation maxima and the
    /// full waveform, preserving spectrum-derived silence/energy metadata.
    #[arg(long, default_value_t = false, conflicts_with = "siri")]
    strings: bool,
}

fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();

    // Guard the render contract: 0 bands → NaN energy → invalid JSON the
    // plugin silently drops (dead mini, no error); absurd counts flood stdout.
    if !(4..=512).contains(&cli.bands) {
        anyhow::bail!(
            "--bands must be 4..=512 (got {})",
            cli.bands
        );
    }
    if !cli.fft_size.is_power_of_two() || !(256..=8192).contains(&cli.fft_size) {
        anyhow::bail!(
            "--fft-size must be a power of two in 256..=8192 (got {})",
            cli.fft_size
        );
    }
    // Resolve the backend up-front (errors on unsupported source).
    let backend = source::resolve(&cli.source)?;
    eprintln!(
        "omaviz-engine: starting (source={}, resolved={}, bands={})",
        cli.source, backend, cli.bands
    );

    let rx = source::spawn(&cli.source)?;

    // Sample rate is discovered from the first audio chunk (pipewire/gen).
    let mut analyzer: Option<Analyzer> = None;
    let mut last: Option<Vec<f32>> = None;
    let mut last_arrival = std::time::Instant::now();
    let stale_after = Duration::from_secs(2);
    let tick = Duration::from_millis(16); // ~60 Hz frame rate

    let mut out = std::io::stdout().lock();
    let mut last_emit = std::time::Instant::now();
    let idle_heartbeat = Duration::from_millis(200); // 5 Hz keepalive
    let mut fresh_chunk = false;
    let mut last_silent = false;
    let mut last_siri_wave: Vec<f32> = Vec::new();
    let mut siri_serial: i32 = 0;
    // Silence grace: after audio goes quiet the renderer still needs
    // ~60 Hz frames to animate the bar/peak fall. Keep the full rate for
    // this window, then drop to the 5 Hz heartbeat.
    let mut silent_since: Option<std::time::Instant> = None;
    let fall_grace = Duration::from_millis(2000);
    loop {
        // Drain all pending events, keeping the most recent per kind.
        let mut pending_chunk: Option<dsp::AudioChunk> = None;
        let mut pending_frame: Option<(Vec<f32>, f32, f32, bool, String)> = None;
        let mut exit = false;
        while let Ok(ev) = rx.try_recv() {
            match ev {
                SourceEvent::Chunk(c) => pending_chunk = Some(c),
                SourceEvent::Frame {
                    bands,
                    energy,
                    beat,
                    silent,
                    source,
                } => pending_frame = Some((bands, energy, beat, silent, source)),
                SourceEvent::Exit => {
                    exit = true;
                    break;
                }
            }
        }
        if exit {
            break;
        }

        if let Some(f) = pending_frame {
            // Recorded-spectrum replay: emit verbatim (analysis = 0).
            let (bands, energy, beat, silent, source) = f;
            let frame = Frame {
                bands: &bands,
                energy,
                beat,
                silent,
                source: &source,
            };
            let line = build_frame(&frame);
            writeln!(out, "{line}")?;
            out.flush()?;
        } else {
            // Raw audio (pipewire / gen): update the analyzer on new chunks, then
            // emit every tick so frames keep flowing at ~60 Hz.
            if let Some(c) = pending_chunk {
                match &mut analyzer {
                    None => analyzer = Some(Analyzer::new(c.rate as f32, cli.bands, cli.fft_size)),
                    Some(a) if (a.sample_rate() as u32) != c.rate => {
                        *a = Analyzer::new(c.rate as f32, cli.bands, cli.fft_size);
                    }
                    _ => {}
                }
                last = Some(c.samples.clone());
                fresh_chunk = true;
                last_arrival = std::time::Instant::now();
            }
            // Capture death: no chunks for 2s (server restart, suspend,
            // thread error) — drop the stale frame and report silence
            // instead of freezing mid-motion bars on screen.
            let stale = last_arrival.elapsed() >= stale_after;
            if stale {
                last = None;
            }
            // Emit on fresh audio only; otherwise a 5 Hz heartbeat so the
            // UI stays alive without 60 identical frames/sec of parse+paint.
            // Steady silence also drops to heartbeat: identical silent
            // frames carry no information (peaks decay client-side).
            let due = last_emit.elapsed() >= idle_heartbeat;
            // Stale source (capture dead): emit explicit zero silence at
            // heartbeat rate so the UI clears instead of holding old bars.
            if stale {
                if due {
                    last_emit = std::time::Instant::now();
                    last_silent = true;
                    write_stale_frame(&mut out, &cli, &backend)?;
                    out.flush()?;
                } else {
                    std::thread::sleep(tick);
                }
                continue;
            }
            if let (Some(a), Some(samples)) = (&mut analyzer, &last) {
                if !(fresh_chunk || due) {
                    std::thread::sleep(tick);
                    continue;
                }
                fresh_chunk = false;
                a.push(samples);
                a.analyze();
                let silent_now = a.is_silent();
                if silent_now {
                    if silent_since.is_none() {
                        silent_since = Some(std::time::Instant::now());
                    }
                } else {
                    silent_since = None;
                }
                let in_grace = silent_now
                    && silent_since
                        .map(|t| t.elapsed() < fall_grace)
                        .unwrap_or(false);
                // Steady silence carries no information ONCE any fall has
                // settled — hold it to the heartbeat rate. During the grace
                // window (and always when audible) keep the full frame rate.
                if silent_now && last_silent && !due && !in_grace {
                    std::thread::sleep(tick);
                    continue;
                }
                last_silent = silent_now;
                last_emit = std::time::Instant::now();
                let drives = if cli.strings { strings_drives(&a.bands) } else { [0.0; 16] };
                let siri_drives = if cli.siri { a.siri_levels() } else { [0.0; 6] };
                let frame = Frame {
                    bands: if cli.siri { &siri_drives } else if cli.strings { &drives } else { &a.bands },
                    energy: a.energy,
                    beat: a.beat,
                    silent: silent_now,
                    source: &backend,
                };
                let mut line = build_frame(&frame);
                if cli.strings || cli.siri {
                    line.pop();
                    line.push_str(if cli.siri { ",\"band_layout\":\"siri\"}" } else { ",\"band_layout\":\"strings\"}" });
                }
                writeln!(out, "{line}")?;
                // Oscilloscope feed: 128-point time-domain snippet on its
                // own line ({wave:[...]}); the plugin parses it separately
                // so spectrum frames stay untouched.
                if cli.wave || cli.siri || cli.strings {
                    let w = a.wave_snippet(128);
                    let w_json: Vec<String> =
                        w.iter().map(|v| format!("{:.4}", v)).collect();
                    if cli.siri {
                        // Retain waveform-change wake identity independently of RMS.
                        // Loudness itself uses all PCM samples to avoid aliasing.
                        let decoded: Vec<f32> = w_json.iter().map(|s| s.parse().unwrap_or(0.0)).collect();
                        if decoded != last_siri_wave {
                            siri_serial = siri_serial % i32::MAX + 1;
                            last_siri_wave = decoded;
                        }
                        writeln!(out, "{{\"wave\":[{:.9}],\"wave_serial\":{}}}",
                                 a.rms_level(), siri_serial)?;
                    } else {
                        writeln!(out, "{{\"wave\":[{}]}}", w_json.join(","))?;
                    }
                }
                out.flush()?;
            }
        }

        std::thread::sleep(tick);
    }

    Ok(())
}

// Capture loss must clear every consumer, preserving the selected wire layout.
fn write_stale_frame(out: &mut impl Write, cli: &Cli, backend: &str) -> std::io::Result<()> {
    let count = if cli.siri { 6 } else if cli.strings { 16 } else { cli.bands };
    let zeros = vec![0.0; count];
    let mut line = build_frame(&Frame {
        bands: &zeros, energy: 0.0, beat: 0.0, silent: true, source: backend,
    });
    if cli.siri || cli.strings {
        line.pop();
        line.push_str(if cli.siri { ",\"band_layout\":\"siri\"}" } else { ",\"band_layout\":\"strings\"}" });
    }
    writeln!(out, "{line}")?;
    if cli.siri {
        writeln!(out, "{{\"wave\":[0],\"wave_serial\":0}}")?;
    } else if cli.wave || cli.strings {
        writeln!(out, "{{\"wave\":[{}]}}", vec!["0"; 128].join(","))?;
    }
    Ok(())
}

fn strings_drives(bands: &[f32]) -> [f32; 16] {
    let mut drives = [0.0_f32; 16];
    if bands.is_empty() { return drives; }
    for (layer, drive) in drives.iter_mut().enumerate() {
        let center = (((layer as f32 + 0.5) / 16.0 * bands.len() as f32) as usize).min(bands.len()-1);
        for tap in -2_isize..=2 {
            let index = (center as isize + tap).clamp(0, bands.len() as isize-1) as usize;
            *drive = drive.max(bands[index].clamp(0.0, 1.0));
        }
    }
    drives
}

#[cfg(test)]
mod strings_tests {
    use super::strings_drives;
    #[test]
    fn capture_loss_clears_all_feeds_without_changing_layout() {
        use super::{Cli, write_stale_frame};
        use clap::Parser;
        for (flag, count, wave_count, layout) in [
            ("", 32, 0, ""), ("--wave", 32, 128, ""),
            ("--siri", 6, 1, "siri"), ("--strings", 16, 128, "strings"),
        ] {
            let mut args = vec!["engine"];
            if !flag.is_empty() { args.push(flag); }
            let cli = Cli::parse_from(args);
            let mut output = Vec::new();
            write_stale_frame(&mut output, &cli, "pipewire").unwrap();
            let lines: Vec<serde_json::Value> = String::from_utf8(output).unwrap().lines()
                .map(|line| serde_json::from_str(line).unwrap()).collect();
            assert_eq!(lines[0]["bands"].as_array().unwrap().len(), count);
            assert!(lines[0]["bands"].as_array().unwrap().iter().all(|v| v == 0.0));
            assert_eq!(lines[0]["silent"], true);
            assert_eq!(lines[0]["band_layout"].as_str().unwrap_or(""), layout);
            assert_eq!(lines.len(), if wave_count > 0 { 2 } else { 1 });
            if wave_count > 0 {
                let wave = lines[1]["wave"].as_array().unwrap();
                assert_eq!(wave.len(), wave_count);
                assert!(wave.iter().all(|v| v.as_f64() == Some(0.0)));
            }
        }
    }
    #[test]
    fn compact_drives_preserve_quantized_five_band_maxima() {
        for count in [4, 16, 32, 128, 256, 512] {
            let bands: Vec<f32> = (0..count).map(|i| ((i as f32 * 0.37).sin()+1.0)*0.5).collect();
            let decoded: Vec<f32> = bands.iter().map(|v| format!("{v:.4}").parse().unwrap()).collect();
            let compact = strings_drives(&bands);
            for (layer, drive) in compact.iter().enumerate() {
                let center = (((layer as f32+0.5)/16.0*count as f32) as usize).min(count-1);
                let mut expected = 0.0_f32;
                for tap in -2_isize..=2 {
                    expected = expected.max(decoded[(center as isize+tap).clamp(0,count as isize-1) as usize]);
                }
                assert_eq!(format!("{drive:.4}").parse::<f32>().unwrap(), expected);
            }
        }
        assert_eq!(strings_drives(&[]), [0.0; 16]);
    }
}
