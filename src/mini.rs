//! Mini mode: waybar custom module. Emits one JSON line per update on stdout.
//!
//! Watches config.toml so settings changes appear in the bar without a waybar
//! restart, and the display-mode file so the bar menu can turn it off.
//!
//! Important: when the mode is `off` we still emit a *visible* dim baseline
//! rather than an empty string. waybar hides a custom module whose text is
//! empty, which would remove the module (and its right-click menu) from the
//! bar entirely — leaving no way to turn it back on. A dim glyph keeps the
//! menu reachable while freezing the visualization.

use crate::config::{Config, Mode};
use crate::ipc::Frame;
use crate::mode;
use anyhow::Result;
use std::io::Write;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

const BLOCKS: [char; 9] = [' ', '▁', '▂', '▃', '▄', '▅', '▆', '▇', '█'];

/// Shown when silent / off: a dim baseline so the module is still visible in
/// the bar. The `.silent` / `.off` CSS classes fade it.
const IDLE_GLYPH: char = '▁';

/// Downsample the band array to `width` glyph columns (peak per column).
fn render_bars(bands: &[f32], width: usize, sensitivity: f32) -> String {
    if bands.is_empty() || width == 0 {
        return String::new();
    }
    let mut s = String::with_capacity(width * 3);
    for i in 0..width {
        let lo = i * bands.len() / width;
        let hi = (((i + 1) * bands.len()) / width)
            .max(lo + 1)
            .min(bands.len());
        let peak = bands[lo..hi].iter().copied().fold(0f32, f32::max) * sensitivity;
        let idx = ((peak.clamp(0.0, 1.0)) * (BLOCKS.len() - 1) as f32).round() as usize;
        s.push(BLOCKS[idx.min(BLOCKS.len() - 1)]);
    }
    s
}

/// A single VU-style meter: one filled run proportional to overall energy.
fn render_vu(energy: f32, width: usize, sensitivity: f32) -> String {
    let filled = ((energy * sensitivity).clamp(0.0, 1.0) * width as f32).round() as usize;
    let mut s = String::with_capacity(width * 3);
    for i in 0..width {
        s.push(if i < filled { '█' } else { '▁' });
    }
    s
}

fn escape(s: &str) -> String {
    s.replace('\\', "\\\\").replace('"', "\\\"")
}

pub fn run(mut cfg: Config, width: usize) -> Result<()> {
    // A reader thread keeps the newest frame in a shared slot, so the bar
    // renders at its own cadence and never lags behind the daemon.
    let shared = Arc::new(Mutex::new(Frame::default()));
    crate::ipc::spawn_reader(shared.clone());

    let mut watcher = crate::config::Watcher::new();
    let out = std::io::stdout();
    let mut out = out.lock();
    let mut last_text = String::new();
    let mut last_class = String::new();
    let mut last_tooltip = String::new();
    // Whether we've ever received a real frame. Until then the module is
    // genuinely "waiting for daemon"; once we have data, silent/active states
    // apply even if the latest frame is empty.
    let mut ever_received = false;

    let fps = cfg.mini.fps.clamp(1, 60);
    let period = Duration::from_secs_f32(1.0 / fps as f32);
    let mut next = Instant::now();

    loop {
        // Hot reload: sensitivity, visual and mini fps take effect live.
        if let Some(new_cfg) = watcher.poll() {
            cfg = new_cfg;
        }

        let show = mode::get().shows_mini();
        let frame = shared.lock().unwrap().clone();
        if !frame.bands.is_empty() {
            ever_received = true;
        }

        // No daemon yet counts as idle, not as "active but blank".
        let idle = frame.silent || frame.bands.is_empty();

        let (text, class) = if !show {
            // OFF: freeze the visualization but keep the module in the bar so
            // its right-click menu stays reachable. A dim baseline, not empty.
            (IDLE_GLYPH.to_string().repeat(width), "off")
        } else if idle {
            // A dim baseline, never nothing, so "installed but quiet" is not
            // mistaken for "broken".
            (IDLE_GLYPH.to_string().repeat(width), "silent")
        } else {
            let visual = cfg.mini.visual.as_str();
            let t = match visual {
                "vu" => render_vu(frame.energy, width, cfg.sensitivity(Mode::Mini)),
                _ => render_bars(&frame.bands, width, cfg.sensitivity(Mode::Mini)),
            };
            (t, "active")
        };

        // Only emit when something actually changed — waybar re-lays-out on
        // every line, so this matters for idle cost. The tooltip key must be
        // part of the change test: "waiting for daemon" (never received a frame)
        // transitions to "silent"/"active" even when the visible glyph string
        // and class are unchanged, so we also track the received-state flip.
        let tooltip = if !show {
            "omaviz — visualization off (right-click to re-enable)".to_string()
        } else if !ever_received {
            "omaviz — waiting for daemon".to_string()
        } else {
            format!(
                "omaviz — {} · energy {:.2}{}",
                cfg.mini.visual,
                frame.energy,
                if frame.silent { " (silent)" } else { "" }
            )
        };
        if text != last_text || class != last_class || tooltip != last_tooltip {
            writeln!(
                out,
                "{{\"text\":\"{}\",\"tooltip\":\"{}\",\"class\":\"{}\"}}",
                escape(&text),
                escape(&tooltip),
                class
            )?;
            out.flush()?;
            last_text = text;
            last_class = class.to_string();
            last_tooltip = tooltip;
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
