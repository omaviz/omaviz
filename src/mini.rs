//! Waybar custom-module client.
//!
//! Emits a JSON line per frame (waybar `return-type: json`). Behavior:
//! - Mini active      -> live bars + "energy" tooltip
//! - Desktop open     -> icon only (empty text, class "icon")
//! - Off / paused     -> dimmed, "right-click to resume" tooltip
//! - Exited (Quit)    -> emit nothing (module hidden via empty-string class)
//!
//! The bars are rendered with unicode block glyphs spanning the full cell
//! height; waybar's line-height is set to 1.0 so a single row fills the bar.

use crate::config::{Config, Watcher};
use crate::ipc::Frame;
use crate::mode;
use std::io::Write;
use std::sync::{Arc, Mutex};

const GLYPHS: &[char] = &['▁', '▂', '▃', '▄', '▅', '▆', '▇', '█'];

pub fn run(mut cfg: Config, width: usize) -> anyhow::Result<()> {
    let out: Arc<Mutex<Box<dyn Write + Send>>> = Arc::new(Mutex::new(Box::new(std::io::stdout())));
    let shared = Arc::new(Mutex::new(Frame::default()));
    crate::ipc::spawn_reader(shared.clone());

    let mut last_text = String::new();
    let mut last_class = String::new();
    let mut last_tooltip = String::new();

    let mut ever_received = false;
    let mut watcher = Watcher::new();

    loop {
        // Hot reload: pick up settings saves without a restart.
        if let Some(new_cfg) = watcher.poll() {
            cfg = new_cfg;
        }

        let m = mode::current();
        let exited = mode::is_exited();

        // Exited (Quit): emit nothing so the module disappears from the bar.
        if exited {
            let line = r#"{"text":"","tooltip":"","class":"hidden"}"#;
            let mut w = out.lock().unwrap();
            if line != last_text {
                let _ = writeln!(w, "{line}");
                let _ = w.flush();
                last_text = line.to_string();
            }
            std::thread::sleep(std::time::Duration::from_millis(500));
            continue;
        }

        // Desktop window open OR paused (Off): render dimmed bars. No live
        // visualization here — the desktop window is showing it (or we're paused).
        // This keeps the module always visible and avoids any waybar reload.
        if m.dimmed() {
            let tooltip = if m.desktop_active() {
                "omaviz — desktop window open (click to close)"
            } else {
                "omaviz — paused (right-click to resume)"
            };
            let line = format!(
                "{{\"text\":\"{}\",\"tooltip\":\"{}\",\"class\":\"off\"}}",
                "▁".repeat(width),
                tooltip
            );
            if line != last_text {
                let mut w = out.lock().unwrap();
                let _ = writeln!(w, "{line}");
                let _ = w.flush();
                last_text = line.clone();
                last_class = "off".to_string();
                last_tooltip = tooltip.to_string();
            }
            std::thread::sleep(std::time::Duration::from_millis(250));
            continue;
        }

        // Mini active: render live bars.
        let frame = mode::decorate(&shared.lock().unwrap().clone());
        if !frame.bands.is_empty() {
            ever_received = true;
        }
        let idle = !ever_received || frame.bands.is_empty() || frame.silent;
        let (text, class, tooltip): (String, &str, String) = if idle {
            (
                "▁".repeat(width),
                "silent",
                "omaviz — silent (no audio)".to_string(),
            )
        } else {
            let cfg_for = cfg.mode(crate::config::Mode::Mini);
            let sens = cfg_for.sensitivity.clamp(0.1, 4.0);
            let _smooth = cfg_for.smoothing.clamp(0.0, 1.0);
            // Per-display fit: gain amplifies quiet audio (so playing is clearly
            // different from flat), floor keeps a minimum bar height so the row
            // never collapses to nothing.
            let gain = cfg_for.extra.get("mini_gain").copied().unwrap_or(1.0).clamp(0.5, 4.0);
            let floor = cfg_for.extra.get("mini_floor").copied().unwrap_or(0.0).clamp(0.0, 0.6);
            let lvl = (cfg.audio.bands.max(1) as f32).min(width as f32) as usize;
            let mut bars = String::new();
            for i in 0..lvl {
                let idx = (i as f32 / lvl as f32 * frame.bands.len() as f32) as usize;
                let mut v = frame.bands[idx.min(frame.bands.len() - 1)] * sens * gain;
                if v < floor {
                    v = floor;
                }
                if v > 1.0 {
                    v = 1.0;
                }
                let gi = (v * (GLYPHS.len() - 1) as f32).round() as usize;
                bars.push(GLYPHS[gi.min(GLYPHS.len() - 1)]);
            }
            let energy = frame.energy;
            let vis = cfg_for.visual.clone();
            (
                bars,
                "active",
                format!("omaviz · {vis} · energy {energy:.2}"),
            )
        };

        if text != last_text || class != last_class || tooltip != last_tooltip {
            if crate::debug() {
                eprintln!("omaviz: mini -> class={class} tooltip='{tooltip}'");
            }
            let line = format!(
                "{{\"text\":\"{}\",\"tooltip\":\"{}\",\"class\":\"{}\"}}",
                text, tooltip, class
            );
            let mut w = out.lock().unwrap();
            let _ = writeln!(w, "{line}");
            let _ = w.flush();
            last_text = text.to_string();
            last_class = class.to_string();
            last_tooltip = tooltip.to_string();
        }

        std::thread::sleep(std::time::Duration::from_millis(if idle { 250 } else { 33 }));
    }
}
