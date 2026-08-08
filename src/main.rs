mod capture;
mod dsp;

use anyhow::Result;
use clap::Parser;
use std::sync::mpsc;
use std::time::{Duration, Instant};

#[derive(Parser)]
#[command(name = "omaviz", about = "Omarchy audio visualizer daemon (step 1)")]
struct Args {
    /// Print a live ASCII spectrum meter to the terminal.
    #[arg(long)]
    debug: bool,
    /// Number of log-spaced bands.
    #[arg(long, default_value_t = 32)]
    bands: usize,
    /// Analysis/output frame rate.
    #[arg(long, default_value_t = 60)]
    fps: u32,
    /// Exit after N seconds (0 = run forever).
    #[arg(long, default_value_t = 0)]
    seconds: u64,
}

fn main() -> Result<()> {
    let args = Args::parse();
    let (tx, rx) = mpsc::channel::<capture::AudioChunk>();

    std::thread::spawn(move || {
        if let Err(e) = capture::run(tx) {
            eprintln!("capture error: {e:#}");
        }
    });

    let mut an = dsp::Analyzer::new(48_000.0, args.bands);
    let period = Duration::from_secs_f64(1.0 / args.fps as f64);
    let start = Instant::now();
    let mut next = Instant::now();
    let mut got_audio = false;

    loop {
        // Drain everything the capture thread produced.
        while let Ok(chunk) = rx.try_recv() {
            got_audio = true;
            an.push(&chunk.samples);
        }
        an.analyze();

        if args.debug {
            if !got_audio {
                print!("\rwaiting for audio on default sink monitor...");
            } else {
                let glyphs = [' ', '.', ':', '-', '=', '+', '*', '#', '%', '@'];
                let bar: String = an
                    .bands
                    .iter()
                    .map(|v| glyphs[((v * 9.0).round() as usize).min(9)])
                    .collect();
                print!(
                    "\r[{bar}] e={:.3} beat={:.2} {}",
                    an.energy,
                    an.beat,
                    if an.is_silent() { "silent " } else { "       " }
                );
            }
            use std::io::Write;
            let _ = std::io::stdout().flush();
        }

        if args.seconds > 0 && start.elapsed().as_secs() >= args.seconds {
            println!();
            break;
        }
        next += period;
        let now = Instant::now();
        if next > now {
            std::thread::sleep(next - now);
        } else {
            next = now;
        }
    }
    Ok(())
}
