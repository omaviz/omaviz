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
}

fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();

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
    let tick = Duration::from_millis(16); // ~60 Hz frame rate

    let mut out = std::io::stdout();
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
                    None => analyzer = Some(Analyzer::new(c.rate as f32, cli.bands)),
                    Some(a) if (a.sample_rate() as u32) != c.rate => {
                        *a = Analyzer::new(c.rate as f32, cli.bands);
                    }
                    _ => {}
                }
                last = Some(c.samples.clone());
            }
            if let (Some(a), Some(samples)) = (&mut analyzer, &last) {
                a.push(samples);
                a.analyze();
                let frame = Frame {
                    bands: &a.bands,
                    energy: a.energy,
                    beat: a.beat,
                    silent: a.is_silent(),
                    source: &backend,
                };
                let line = build_frame(&frame);
                writeln!(out, "{line}")?;
                out.flush()?;
            }
        }

        std::thread::sleep(tick);
    }

    Ok(())
}
