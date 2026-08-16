mod capture;
mod client;
mod config;
mod dsp;
mod instance;
mod ipc;
mod logging;
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
use logging::{init_daemon};
use mode::Mode as AppMode;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc;
use std::time::{Duration, Instant};

/// Global debug flag, set from the `--debug` CLI flag (and inherited by child
/// `omaviz` processes via OMAVIZ_DEBUG so spawned windows also log).
static DEBUG: AtomicBool = AtomicBool::new(false);

pub fn debug() -> bool {
    DEBUG.load(Ordering::Relaxed)
}

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
        /// Print a live ASCII meter instead of running silent (debugging).
        #[arg(long)]
        debug: bool,
    },
    /// Small floating visualizer window.
    Desktop,
    /// Fullscreen visualizer.
    Full,
    /// Waybar custom module (JSON lines on stdout).
    Mini {
        #[arg(long, default_value_t = 18)]
        width: usize,
    },
    /// Settings panel.
    Settings,
    /// List available visualizations.
    Visuals,
    /// Print the config file path.
    Config,
    /// Get or set the mode (off | mini | desktop).
    Mode {
        /// New mode. Omit to print the current one.
        value: Option<String>,
    },
    /// Toggle the desktop window (left-click on the waybar module).
    Toggle,
    /// Pause the visualization (Off). Mini module stays, dimmed.
    Off,
    /// Exit the whole app: stop daemon, remove from waybar, close window.
    Quit,
    /// Tell the daemon the desktop window was closed by the user.
    WindowClosed,
    /// Signal the desktop window to close itself.
    WindowClose,
    /// App-launch entry point: ensure daemon + mini module are present.
    Start,
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
    /// Set the visualization for a mode, e.g. `omaviz select mini fire`.
    Select {
        /// desktop | full | mini
        target: String,
        /// Visualization name.
        visual: String,
    },
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    DEBUG.store(cli.debug, Ordering::Relaxed);
    if cli.debug {
        // Set debug flag for child processes. Safe at this point as we're
        // single-threaded in main() before any threads are spawned.
        // std::env::set_var is unsafe in Rust 2024+ because it's not thread-safe,
        // but we're in single-threaded main() before spawning any threads.
        unsafe { std::env::set_var("OMAVIZ_DEBUG", "1") };
    }
    let cfg = Config::load_or_init()?;

    match cli.cmd.unwrap_or(Cmd::Start) {
        Cmd::Daemon { seconds, debug } => run_daemon(cfg, debug, seconds),
        Cmd::Desktop => {
            // Launching the desktop window directly flips the mode to Desktop
            // (or removes the Off pause), so the client does not self-close.
            let cur = mode::current();
            if cur != AppMode::Desktop {
                mode::apply(AppMode::Desktop)?;
            }
            client::run(Mode::Desktop, cfg)
        }
        Cmd::Full => {
            let cur = mode::current();
            if cur != AppMode::Desktop {
                mode::apply(AppMode::Desktop)?;
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
                None => println!("{}", mode::current()),
                Some(v) => {
                    let Some(m) = AppMode::parse(&v) else {
                        anyhow::bail!("unknown mode '{v}' (off|mini|desktop)");
                    };
                    mode::apply(m)?;
                    println!("{}", m);
                }
            }
            Ok(())
        }

        Cmd::Toggle => {
            mode::toggle()?;
            println!("{}", mode::current());
            Ok(())
        }

        Cmd::Off => {
            mode::off()?;
            println!("off");
            Ok(())
        }

        Cmd::Quit => {
            mode::quit()?;
            println!("quit");
            Ok(())
        }

        Cmd::WindowClosed => {
            mode::window_closed();
            Ok(())
        }

        Cmd::WindowClose => {
            // Ask any running desktop/full window client to close (so it emits
            // `window-closed` and falls back to Mini). Target only the window
            // clients, not the daemon or other omaviz processes.
            // Use the instance lock files to find the PIDs more precisely.
            let _ = std::process::Command::new("pkill")
                .args(["-f", "^omaviz (desktop|full)$"])
                .status();
            Ok(())
        }

        Cmd::Start => {
            // App-launch entry point. Ensure daemon is up and the mini module is
            // present (re-added if previously removed by Quit). If we were
            // paused (Off) and not exited, resume to Mini.
            ensure_daemon()?;
            ensure_waybar_module()?;
            if !mode::is_exited() {
                mode::set_exited(false);
                mode::set_paused(false);
                if mode::current() != AppMode::Mini {
                    mode::apply(AppMode::Mini)?;
                }
            }
            // Refresh so the module reflects state.
            mode::refresh_waybar();
            println!("{}", mode::current());
            Ok(())
        }

        Cmd::Menu { out } => {
            match out {
                // Regenerate the GtkBuilder XML menu file (used by install/start
                // and exposed as a debug artifact).
                Some(path) => {
                    if let Some(parent) = path.parent() {
                        std::fs::create_dir_all(parent)?;
                    }
                    let (xml, actions) = menu::generate(&mode::current().to_string());
                    std::fs::write(&path, xml)?;
                    println!("{}", path.display());
                    println!("{actions}");
                    Ok(())
                }
                // Right-click with no --out: pop the interactive menu (walker
                // --dmenu with icons + preselection) and dispatch the chosen
                // action. This is the user-facing right-click path.
                None => menu::pop(&cfg.mode(crate::config::Mode::Mini).visual),
            }
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
            if visual::find(&visual).is_none() {
                anyhow::bail!("no visualization named '{visual}'");
            }
            let mut cfg = cfg;
            cfg.set_visual_all(&visual);
            cfg.save()?;
            println!("{target} -> {visual}");
            Ok(())
        }
    }
}

/// Ensure the daemon service is running (start it via systemd if needed).
fn ensure_daemon() -> Result<()> {
    let active = std::process::Command::new("systemctl")
        .args(["--user", "is-active", "--quiet", "omaviz.service"])
        .status()
        .map(|s| s.success())
        .unwrap_or(false);
    if !active {
        std::process::Command::new("systemctl")
            .args(["--user", "start", "omaviz.service"])
            .status()?;
    }
    Ok(())
}

/// Re-add the waybar module if it was removed by Quit.
fn ensure_waybar_module() -> Result<()> {
    mode::set_exited(false);
    // If the module was physically removed from the waybar config by Quit,
    // re-splice it (absolute path + regenerated menu). This is what makes the
    // mini module "come back" after a relaunch.
    mode::add_waybar_module();
    Ok(())
}

fn run_daemon(mut cfg: Config, debug: bool, seconds: Option<u64>) -> Result<()> {
    // Initialize daemon-specific logging
    init_daemon(debug);

    let Some(_guard) = instance::acquire(crate::instance::WindowKind::Daemon)? else {
        anyhow::bail!("omaviz daemon is already running");
    };

    let (tx, rx) = mpsc::channel::<capture::AudioChunk>();
    std::thread::spawn(move || {
        if let Err(e) = capture::run(tx) {
            tracing::error!("omaviz: capture error: {e:#}");
        }
    });

    let mut server = ipc::Server::bind()?;
    tracing::info!(
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
    let mut last_cc: usize = usize::MAX;

    loop {
        // Hot reload: rebuild the analyzer only when the band count changes.
        if let Some(new_cfg) = watcher.poll() {
            if new_cfg.audio.bands.max(1) != cfg.audio.bands.max(1) {
                an = dsp::Analyzer::new(an.sample_rate(), new_cfg.audio.bands.max(1));
            }
            cfg = new_cfg;
        }

        server.accept_pending();

        if crate::debug() {
            let cc = server.client_count();
            if cc != last_cc {
                tracing::debug!("omaviz: daemon clients = {cc}");
                last_cc = cc;
            }
        }

        // Use blocking recv with timeout instead of busy-wait try_recv
        // This eliminates the CPU spin when no audio is coming in
        match rx.recv_timeout(period) {
            Ok(chunk) => {
                // Follow the device's real rate: rebuild if the sink changes to a
                // differently-clocked device (44.1k vs 48k), otherwise band edges
                // would be wrong.
                if chunk.rate > 0 && (chunk.rate as f32 - an.sample_rate()).abs() > 1.0 {
                    an = dsp::Analyzer::new(chunk.rate as f32, cfg.audio.bands.max(1));
                }
                got_audio = true;
                an.push(&chunk.samples);

                // Drain any additional chunks that arrived while we were processing
                while let Ok(chunk) = rx.try_recv() {
                    if chunk.rate > 0 && (chunk.rate as f32 - an.sample_rate()).abs() > 1.0 {
                        an = dsp::Analyzer::new(chunk.rate as f32, cfg.audio.bands.max(1));
                    }
                    an.push(&chunk.samples);
                }
            }
            Err(mpsc::RecvTimeoutError::Timeout) => {
                // Timeout is expected - no audio data this period
            }
            Err(mpsc::RecvTimeoutError::Disconnected) => {
                tracing::warn!("Audio capture channel disconnected, exiting daemon");
                break;
            }
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
            // Sleep longer when idle (200ms instead of 16ms)
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
                tracing::debug!("waiting for audio on default sink monitor...");
            } else {
                let glyphs = [' ', '.', ':', '-', '=', '+', '*', '#', '%', '@'];
                let bar: String = an
                    .bands
                    .iter()
                    .map(|v| glyphs[((v * 9.0).round() as usize).min(9)])
                    .collect();
                tracing::debug!(
                    "[{}] e={:.3} beat={:.2} clients={} {}",
                    bar,
                    an.energy,
                    an.beat,
                    server.client_count(),
                    if an.is_silent() { "silent" } else { "" }
                );
            }
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
