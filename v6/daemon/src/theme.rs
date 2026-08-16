//! Omarchy theme integration.
//!
//! Light/dark is detected from the active theme (light themes ship a
//! `light.mode` marker file); the accent and background colours are read from
//! the theme's `colors.toml`. Everything here is a *default* — the user can
//! override any of it in config.toml (`palette.source = "manual"`).

use std::path::PathBuf;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Appearance {
    Light,
    Dark,
}

#[derive(Debug, Clone)]
pub struct Theme {
    pub appearance: Appearance,
    pub accent: [f32; 3],
    pub background: [f32; 3],
    pub foreground: [f32; 3],
}

impl Default for Theme {
    fn default() -> Self {
        Theme {
            appearance: Appearance::Dark,
            accent: [0.15, 0.75, 0.95],
            background: [0.02, 0.02, 0.04],
            foreground: [0.85, 0.85, 0.88],
        }
    }
}

fn theme_dir() -> PathBuf {
    let cfg = std::env::var("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
            PathBuf::from(std::env::var("HOME").unwrap_or_else(|_| "/tmp".into())).join(".config")
        });
    cfg.join("omarchy/current/theme")
}

fn parse_hex(s: &str) -> Option<[f32; 3]> {
    let h = s.trim().trim_matches('"').trim_start_matches('#');
    if h.len() < 6 {
        return None;
    }
    let r = u8::from_str_radix(&h[0..2], 16).ok()?;
    let g = u8::from_str_radix(&h[2..4], 16).ok()?;
    let b = u8::from_str_radix(&h[4..6], 16).ok()?;
    Some([r as f32 / 255.0, g as f32 / 255.0, b as f32 / 255.0])
}

fn relative_luminance(c: [f32; 3]) -> f32 {
    0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
}

/// Read the current Omarchy theme. Falls back to sane dark defaults.
pub fn detect() -> Theme {
    let dir = theme_dir();
    let mut t = Theme::default();

    // colors.toml is a flat `key = "#rrggbb"` list.
    if let Ok(text) = std::fs::read_to_string(dir.join("colors.toml")) {
        for line in text.lines() {
            let Some((k, v)) = line.split_once('=') else {
                continue;
            };
            let (k, v) = (k.trim(), v.trim());
            match k {
                "accent" => {
                    if let Some(c) = parse_hex(v) {
                        t.accent = c;
                    }
                }
                "background" => {
                    if let Some(c) = parse_hex(v) {
                        t.background = c;
                    }
                }
                "foreground" => {
                    if let Some(c) = parse_hex(v) {
                        t.foreground = c;
                    }
                }
                _ => {}
            }
        }
    }

    // Omarchy light themes ship a `light.mode` marker; otherwise infer from the
    // background's luminance so third-party themes still work.
    t.appearance = if dir.join("light.mode").exists() {
        Appearance::Light
    } else if relative_luminance(t.background) > 0.5 {
        Appearance::Light
    } else {
        Appearance::Dark
    };

    t
}

impl Theme {
    /// A complementary second colour for gradients, derived from the accent by
    /// rotating hue — keeps omaviz on-theme without a second theme variable.
    pub fn accent_secondary(&self) -> [f32; 3] {
        let [r, g, b] = self.accent;
        // Cheap hue rotation ~140 degrees via channel remix.
        [
            (b * 0.85 + g * 0.15).clamp(0.0, 1.0),
            (r * 0.65 + b * 0.35).clamp(0.0, 1.0),
            (g * 0.80 + r * 0.20).clamp(0.0, 1.0),
        ]
    }

    /// Visualization background for this theme, at the requested opacity.
    pub fn viz_background(&self, opacity: f32) -> [f32; 4] {
        let base = match self.appearance {
            // Light themes: a near-white tint, not the theme's raw background,
            // so bars stay legible.
            Appearance::Light => {
                let l = |c: f32| (c * 0.25 + 0.75).clamp(0.0, 1.0);
                [
                    l(self.background[0]),
                    l(self.background[1]),
                    l(self.background[2]),
                ]
            }
            Appearance::Dark => {
                let d = |c: f32| (c * 0.6).clamp(0.0, 1.0);
                [
                    d(self.background[0]),
                    d(self.background[1]),
                    d(self.background[2]),
                ]
            }
        };
        [base[0], base[1], base[2], opacity.clamp(0.0, 1.0)]
    }

    pub fn is_light(&self) -> bool {
        self.appearance == Appearance::Light
    }
}
