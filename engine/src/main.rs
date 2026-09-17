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

    /// Bar motion: exp (attack/decay easing, default) or linear
    /// (Winamp-style: instant rise, fixed-rate fall).
    #[arg(long, default_value = "exp")]
    fall_mode: String,

    /// FFT window size in samples (window latency = size/rate, e.g.
    /// 2048 @48kHz ≈ 43ms, 1024 ≈ 21ms). Smaller is snappier but
    /// coarsens bass resolution. Must be a power of two.
    #[arg(long, default_value_t = 2048)]
    fft_size: usize,

    /// Append a 128-point downsampled time-domain snippet ("wave") per
    /// frame for the oscilloscope renderer. Adds ~0.7KB/line.
    #[arg(long, default_value_t = false)]
    wave: bool,
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
    let linear_fall = match cli.fall_mode.as_str() {
        "linear" => true,
        "exp" => false,
        other => anyhow::bail!("--fall-mode must be exp|linear (got {other})"),
    };

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
                    None => analyzer = Some(Analyzer::new(c.rate as f32, cli.bands, cli.fft_size, linear_fall)),
                    Some(a) if (a.sample_rate() as u32) != c.rate => {
                        *a = Analyzer::new(c.rate as f32, cli.bands, cli.fft_size, linear_fall);
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
                    let zeros = vec![0.0f32; cli.bands];
                    let frame = Frame {
                        bands: &zeros,
                        energy: 0.0,
                        beat: 0.0,
                        silent: true,
                        source: &backend,
                    };
                    let line = build_frame(&frame);
                    writeln!(out, "{line}")?;
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
                // Steady silence carries no information — hold it to the
                // heartbeat rate instead of re-emitting 60 identical frames.
                if silent_now && last_silent && !due {
                    std::thread::sleep(tick);
                    continue;
                }
                last_silent = silent_now;
                last_emit = std::time::Instant::now();
                let frame = Frame {
                    bands: &a.bands,
                    energy: a.energy,
                    beat: a.beat,
                    silent: silent_now,
                    source: &backend,
                };
                let line = build_frame(&frame);
                writeln!(out, "{line}")?;
                // Oscilloscope feed: 128-point time-domain snippet on its
                // own line ({wave:[...]}); the plugin parses it separately
                // so spectrum frames stay untouched.
                if cli.wave {
                    let w = a.wave_snippet(128);
                    let w_json: Vec<String> =
                        w.iter().map(|v| format!("{:.4}", v)).collect();
                    writeln!(out, "{{\"wave\":[{}]}}", w_json.join(","))?;
                }
                out.flush()?;
            }
        }

        std::thread::sleep(tick);
    }

    Ok(())
}
