//! Mini mode: waybar custom module. Emits one JSON line per update on stdout.
//! Limited visual selection by design — Unicode block bars / VU meter.

use crate::config::Config;
use crate::ipc::Frame;
use anyhow::Result;
use std::io::Write;
use std::time::{Duration, Instant};

const BLOCKS: [char; 9] = [' ', '▁', '▂', '▃', '▄', '▅', '▆', '▇', '█'];

/// Downsample the band array to `width` glyph columns (peak per column).
fn render_bars(bands: &[f32], width: usize, sensitivity: f32) -> String {
    if bands.is_empty() || width == 0 {
        return " ".repeat(width);
    }
    let mut out = String::with_capacity(width * 3);
    for i in 0..width {
        let lo = i * bands.len() / width;
        let hi = (((i + 1) * bands.len()) / width)
            .max(lo + 1)
            .min(bands.len());
        let peak = bands[lo..hi].iter().copied().fold(0.0f32, f32::max) * sensitivity;
        let idx = ((peak.clamp(0.0, 1.0) * 8.0).round() as usize).min(8);
        out.push(BLOCKS[idx]);
    }
    out
}

fn render_vu(energy: f32, width: usize, sensitivity: f32) -> String {
    let filled = ((energy * sensitivity).clamp(0.0, 1.0) * width as f32).round() as usize;
    let mut s = String::with_capacity(width * 3);
    for i in 0..width {
        s.push(if i < filled { '█' } else { '░' });
    }
    s
}

fn escape(s: &str) -> String {
    s.replace('\\', "\\\\").replace('"', "\\\"")
}

pub fn run(cfg: &Config, width: usize, visual: &str) -> Result<()> {
    let fps = if cfg.mini.fps == 0 { 30 } else { cfg.mini.fps };
    let period = Duration::from_secs_f64(1.0 / fps as f64);
    let stdout = std::io::stdout();
    let mut out = stdout.lock();

    // A reader thread keeps the newest frame in a shared slot, so the bar
    // renders at its own cadence and never lags behind the daemon.
    let shared = std::sync::Arc::new(std::sync::Mutex::new(Frame::default()));
    crate::client::spawn_frame_reader(shared.clone());

    let mut next = Instant::now();
    let mut last_text = String::new();

    loop {
        let frame = shared.lock().unwrap().clone();

        let text = if frame.silent || frame.bands.is_empty() {
            " ".repeat(width)
        } else {
            match visual {
                "vu" => render_vu(frame.energy, width, cfg.sensitivity),
                _ => render_bars(&frame.bands, width, cfg.sensitivity),
            }
        };

        // Only emit when the rendered glyphs actually changed — waybar
        // re-lays-out on every line, so this matters for idle cost.
        if text != last_text {
            let tooltip = format!(
                "omaviz — energy {:.2}{}",
                frame.energy,
                if frame.silent { " (silent)" } else { "" }
            );
            writeln!(
                out,
                "{{\"text\":\"{}\",\"tooltip\":\"{}\",\"class\":\"{}\"}}",
                escape(&text),
                escape(&tooltip),
                if frame.silent { "silent" } else { "active" }
            )?;
            out.flush()?;
            last_text = text;
        }

        next += period;
        let now = Instant::now();
        if next > now {
            std::thread::sleep(next - now);
        } else {
            next = now;
        }
    }
}
