mod capture;
mod client;
mod config;
mod dsp;
mod instance;
mod ipc;
mod menu;
mod mini;
mod mode;
mod render;
mod settings;
mod theme;
mod visual;

use anyhow::Result;
use clap::{Parser, Subcommand};
use config::{Config, Mode};
use mode::DisplayMode;
use std::sync::mpsc;
use std::time::{Duration, Instant};

#[derive(Parser)]
#[command(name = "omaviz", version, about = "Omarchy audio visualizer")]
struct Cli {
    #[command(subcommand)]
    cmd: Option<Cmd>,

    /// Print an ASCII meter instead of running a client (debugging).
    #[arg(long, global = true)]
    debug: bool,
}

#[derive(Subcommand)]
enum Cmd {
    /// Capture audio and broadcast spectrum frames (run under systemd).
    Daemon {
        /// Stop after N seconds (testing).
        #[arg(long)]
        seconds: Option<u64>,
    },
    /// Small floating visualizer window.
    Desktop,
    /// Fullscreen visualizer.
    Full,
    /// Waybar custom module (JSON lines on stdout).
    Mini {
        #[arg(long, default_value_t = 14)]
        width: usize,
    },
    /// Settings panel.
    Settings,
    /// List available visualizations.
    Visuals,
    /// Print the config file path.
    Config,
    /// Get or set the display mode (off | mini | desktop | mini+desktop).
    Mode {
        /// New mode. Omit to print the current one.
        value: Option<String>,
    },
    /// Toggle the desktop window (used by the waybar left-click).
    Toggle,
    /// Regenerate the waybar right-click menu from the installed visuals.
    Menu {
        /// Where to write the GtkBuilder XML.
        #[arg(long)]
        out: Option<std::path::PathBuf>,
    },
    /// Nudge sensitivity, e.g. `omaviz sensitivity +0.1` (bar scroll wheel).
    Sensitivity {
        /// Signed delta such as +0.1 / -0.1, or an absolute value like 1.5.
        #[arg(allow_hyphen_values = true)]
        delta: String,
    },
    /// Set the visualization for a mode, e.g. `omaviz select mini vu`.
    Select {
        /// desktop | full | mini
        target: String,
        /// Visualization name.
        visual: String,
    },
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    let cfg = Config::load_or_init()?;

    match cli.cmd.unwrap_or(Cmd::Desktop) {
        Cmd::Daemon { seconds } => run_daemon(cfg, cli.debug, seconds),
        Cmd::Desktop => {
            // Launching the desktop window directly must also flip the display
            // mode on, or the client would spawn and immediately self-close
            // (the client closes itself when the mode stops showing desktop).
            let cur = mode::get();
            if !cur.shows_desktop() {
                let next = if cur == mode::DisplayMode::Off {
                    mode::DisplayMode::Desktop
                } else {
                    mode::DisplayMode::MiniDesktop
                };
                mode::apply(next)?;
            }
            client::run(Mode::Desktop, cfg)
        }
        Cmd::Full => {
            let cur = mode::get();
            if !cur.shows_desktop() {
                let next = if cur == mode::DisplayMode::Off {
                    mode::DisplayMode::Desktop
                } else {
                    mode::DisplayMode::MiniDesktop
                };
                mode::apply(next)?;
            }
            client::run(Mode::Full, cfg)
        }
        Cmd::Mini { width } => mini::run(cfg, width),
        Cmd::Settings => settings::run(cfg),

        Cmd::Visuals => {
            for v in visual::discover() {
                println!("{}", v.name);
            }
            Ok(())
        }

        Cmd::Config => {
            println!("{}", config::config_path().display());
            Ok(())
        }

        Cmd::Mode { value } => {
            match value {
                None => println!("{}", mode::get().as_str()),
                Some(v) => {
                    let Some(m) = DisplayMode::parse(&v) else {
                        anyhow::bail!("unknown mode '{v}' (off|mini|desktop|mini+desktop)");
                    };
                    mode::apply(m)?;
                    println!("{}", m.as_str());
                }
            }
            Ok(())
        }

        Cmd::Toggle => {
            let m = mode::toggle_desktop()?;
            println!("{}", m.as_str());
            Ok(())
        }

        Cmd::Menu { out } => {
            let path = out.unwrap_or_else(|| {
                let cfg = std::env::var("XDG_CONFIG_HOME")
                    .map(std::path::PathBuf::from)
                    .unwrap_or_else(|_| {
                        std::path::PathBuf::from(std::env::var("HOME").unwrap_or_default())
                            .join(".config")
                    });
                cfg.join("waybar/omaviz-menu.xml")
            });
            let (xml, actions) = menu::generate(&mode::get().as_str());
            if let Some(parent) = path.parent() {
                std::fs::create_dir_all(parent)?;
            }
            std::fs::write(&path, xml)?;
            // Print the matching menu-actions so install.sh can splice it in.
            println!("{}", path.display());
            println!("{actions}");
            Ok(())
        }

        Cmd::Sensitivity { delta } => {
            let mut cfg = cfg;
            let d = delta.trim();
            cfg.audio.sensitivity = if let Some(rest) = d.strip_prefix('+') {
                cfg.audio.sensitivity + rest.parse::<f32>()?
            } else if d.starts_with('-') {
                cfg.audio.sensitivity + d.parse::<f32>()?
            } else {
                d.parse::<f32>()?
            }
            .clamp(0.1, 4.0);
            cfg.save()?;
            println!("sensitivity {:.2}", cfg.audio.sensitivity);
            Ok(())
        }

        Cmd::Select { target, visual } => {
            let mut cfg = cfg;
            let m = match target.as_str() {
                "desktop" => Mode::Desktop,
                "full" => Mode::Full,
                "mini" => Mode::Mini,
                other => anyhow::bail!("unknown target '{other}' (desktop|full|mini)"),
            };
            if visual::find(&visual).is_none() {
                anyhow::bail!("no visualization named '{visual}'");
            }
            cfg.mode_mut(m).visual = visual.clone();
            cfg.save()?;
            println!("{target} -> {visual}");
            Ok(())
        }
    }
}

fn run_daemon(mut cfg: Config, debug: bool, seconds: Option<u64>) -> Result<()> {
    let Some(_guard) = instance::acquire(crate::instance::WindowKind::Daemon)? else {
        anyhow::bail!("omaviz daemon is already running");
    };

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

    let mut an = dsp::Analyzer::new(48_000.0, cfg.audio.bands.max(1));
    let mut watcher = config::Watcher::new();

    let period = Duration::from_secs_f64(1.0 / 60.0);
    let start = Instant::now();
    let mut next = Instant::now();
    let mut got_audio = false;
    let mut idle_ticks: u32 = 0;

    loop {
        // Hot reload: rebuild the analyzer only when the band count changes.
        if let Some(new_cfg) = watcher.poll() {
            if new_cfg.audio.bands.max(1) != cfg.audio.bands.max(1) {
                an = dsp::Analyzer::new(an.sample_rate(), new_cfg.audio.bands.max(1));
            }
            cfg = new_cfg;
        }

        server.accept_pending();

        while let Ok(chunk) = rx.try_recv() {
            // Follow the device's real rate: rebuild if the sink changes to a
            // differently-clocked device (44.1k vs 48k), otherwise band edges
            // would be wrong.
            if chunk.rate > 0 && (chunk.rate as f32 - an.sample_rate()).abs() > 1.0 {
                an = dsp::Analyzer::new(chunk.rate as f32, cfg.audio.bands.max(1));
            }
            got_audio = true;
            an.push(&chunk.samples);
        }

        // Idle gating: with no clients attached and no sound, skip the FFT
        // entirely and slow the loop right down.
        let has_clients = server.client_count() > 0;
        if !has_clients && an.is_silent() && !debug {
            idle_ticks = idle_ticks.saturating_add(1);
        } else {
            idle_ticks = 0;
        }

        if idle_ticks > 60 {
            std::thread::sleep(Duration::from_millis(200));
            next = Instant::now();
            if let Some(s) = seconds {
                if start.elapsed().as_secs() >= s {
                    break;
                }
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

        if let Some(s) = seconds {
            if start.elapsed().as_secs() >= s {
                if debug {
                    println!();
                }
                break;
            }
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
