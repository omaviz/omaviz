mod capture;
mod client;
mod config;
mod dsp;
mod ipc;
mod mini;
mod render;
mod settings;

use anyhow::Result;
use clap::{Parser, Subcommand};
use config::{Config, Mode};
use std::sync::mpsc;
use std::time::{Duration, Instant};

#[derive(Parser)]
#[command(name = "omaviz", version, about = "Omarchy audio visualizer")]
struct Args {
    #[command(subcommand)]
    cmd: Option<Cmd>,
}

#[derive(Subcommand)]
enum Cmd {
    /// Run the capture + DSP daemon (serves all visualization modes).
    Daemon {
        /// Print a live ASCII spectrum meter instead of staying quiet.
        #[arg(long)]
        debug: bool,
        #[arg(long)]
        bands: Option<usize>,
        #[arg(long, default_value_t = 60)]
        fps: u32,
        /// Exit after N seconds (0 = forever). Testing aid.
        #[arg(long, default_value_t = 0)]
        seconds: u64,
    },
    /// Desktop mode: small standalone window.
    Desktop,
    /// Full mode: fullscreen visualization.
    Full,
    /// Mini mode: waybar custom module (JSON lines on stdout).
    Mini {
        #[arg(long, default_value_t = 12)]
        width: usize,
        /// "bars" or "vu".
        #[arg(long)]
        visual: Option<String>,
    },
    /// Open the settings panel.
    Settings,
    /// List available visualizations.
    Visuals,
    /// Print the resolved config path and contents.
    Config,
}

fn main() -> Result<()> {
    let args = Args::parse();
    let cfg = Config::load_or_init()?;

    match args.cmd.unwrap_or(Cmd::Desktop) {
        Cmd::Daemon {
            debug,
            bands,
            fps,
            seconds,
        } => run_daemon(cfg, debug, bands, fps, seconds),
        Cmd::Desktop => client::run(cfg, Mode::Desktop),
        Cmd::Full => client::run(cfg, Mode::Full),
        Cmd::Mini { width, visual } => {
            let v = visual.unwrap_or_else(|| cfg.mini.visual.clone());
            mini::run(&cfg, width, &v)
        }
        Cmd::Settings => settings::run(cfg),
        Cmd::Visuals => {
            for v in render::list_visuals() {
                println!("{v}");
            }
            Ok(())
        }
        Cmd::Config => {
            println!("# {}", config::config_path().display());
            println!("{}", toml::to_string_pretty(&cfg)?);
            Ok(())
        }
    }
}

fn run_daemon(
    cfg: Config,
    debug: bool,
    bands: Option<usize>,
    fps: u32,
    seconds: u64,
) -> Result<()> {
    let n_bands = bands.unwrap_or(cfg.bands).max(1);
    let (tx, rx) = mpsc::channel::<capture::AudioChunk>();

    std::thread::spawn(move || {
        if let Err(e) = capture::run(tx) {
            eprintln!("omaviz: capture error: {e:#}");
        }
    });

    let mut server = ipc::Server::bind()?;
    eprintln!(
        "omaviz: daemon listening on {}",
        ipc::socket_path().display()
    );

    let mut an = dsp::Analyzer::new(48_000.0, n_bands);
    let period = Duration::from_secs_f64(1.0 / fps as f64);
    let start = Instant::now();
    let mut next = Instant::now();
    let mut got_audio = false;
    let mut idle_ticks: u32 = 0;

    loop {
        server.accept_pending();

        while let Ok(chunk) = rx.try_recv() {
            got_audio = true;
            an.push(&chunk.samples);
        }

        // Idle gating: with no clients attached and no sound, skip the FFT
        // entirely and slow the loop right down.
        let has_clients = server.client_count() > 0;
        let silent = an.is_silent();
        if !has_clients && silent && !debug {
            idle_ticks = idle_ticks.saturating_add(1);
        } else {
            idle_ticks = 0;
        }

        if idle_ticks > 60 {
            std::thread::sleep(Duration::from_millis(200));
            next = Instant::now();
            if seconds > 0 && start.elapsed().as_secs() >= seconds {
                break;
            }
            continue;
        }

        an.analyze();

        let frame = ipc::Frame {
            bands: an.bands.clone(),
            energy: an.energy,
            beat: an.beat,
            silent: an.is_silent(),
        };
        server.broadcast(&frame);

        if debug {
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
                    "\r[{bar}] e={:.3} beat={:.2} clients={} {}",
                    an.energy,
                    an.beat,
                    server.client_count(),
                    if an.is_silent() { "silent " } else { "       " }
                );
            }
            use std::io::Write;
            let _ = std::io::stdout().flush();
        }

        if seconds > 0 && start.elapsed().as_secs() >= seconds {
            if debug {
                println!();
            }
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
