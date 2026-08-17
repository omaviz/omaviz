//! omaviz-engine — the single bundled audio engine for the omaviz plugin.
//!
//! Replaces the old (daemon + socket + bridge) topology. It captures from the
//! active audio source, runs the FFT analyzer, and emits one JSON spectrum
//! frame per line on stdout. The Quickshell plugin spawns this binary and
//! parses stdout with Model.parseSpectrumLine — no socket, no systemd, no
//! separate binaries outside the plugin directory.
//!
//! Backend selection is auto by default: since only PipeWire is compiled in
//! this build, "auto" resolves to PipeWire. Future backends are selected via
//! `--source`.

mod dsp;
mod frame;
mod source;

use clap::Parser;
use dsp::{Analyzer, AudioChunk};
use frame::{build_frame, Frame};
use std::io::Write;
use std::sync::mpsc::Receiver;
use std::time::Duration;

#[derive(Parser, Debug)]
#[command(name = "omaviz-engine", about = "omaviz audio capture + spectrum engine")]
struct Cli {
    /// Audio source backend. v7 supports "auto"/"pipewire".
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

    let rx: Receiver<AudioChunk> = source::spawn(&cli.source)?;

    // Sample rate is discovered from the first audio chunk.
    let mut analyzer: Option<Analyzer> = None;
    let mut last: Option<Vec<f32>> = None;
    let tick = Duration::from_millis(16); // ~60 Hz frame rate

    let mut out = std::io::stdout();
    loop {
        // Drain all pending chunks, keep the most recent.
        while let Ok(chunk) = rx.try_recv() {
            match &mut analyzer {
                None => analyzer = Some(Analyzer::new(chunk.rate as f32, cli.bands)),
                Some(a) if (a.sample_rate() as u32) != chunk.rate => {
                    *a = Analyzer::new(chunk.rate as f32, cli.bands);
                }
                _ => {}
            }
            last = Some(chunk.samples);
        }

        if let (Some(a), Some(samples)) = (&mut analyzer, &last) {
            a.push(samples);
            a.analyze();

            let f = Frame {
                bands: &a.bands,
                energy: a.energy,
                beat: a.beat,
                silent: a.is_silent(),
                source: &backend,
            };
            let line = build_frame(&f);
            writeln!(out, "{line}")?;
            out.flush()?;
        }

        std::thread::sleep(tick);
    }
}
