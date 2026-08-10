//! TOML config + per-visual parameters + hot-reload watching.
//!
//! Layout: one section per mode (`[desktop]` / `[full]` / `[mini]`), plus a
//! shared `[audio]` block of defaults that each mode inherits unless it
//! overrides them. This keeps "change sensitivity once for everything" working
//! while still allowing a mode to tweak (e.g. mini wants denser bars).

use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::path::PathBuf;
use std::time::{Duration, SystemTime};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Config {
    /// Shared audio defaults inherited by every mode section.
    pub audio: Audio,
    pub desktop: ModeConfig,
    pub full: ModeConfig,
    pub mini: ModeConfig,
    pub palette: Palette,
    /// Per-visualization knob values: visuals[<visual>][<param>] = value.
    pub visuals: BTreeMap<String, BTreeMap<String, f32>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Audio {
    pub sensitivity: f32,
    pub smoothing: f32,
    pub bands: usize,
}

impl Default for Audio {
    fn default() -> Self {
        Audio {
            sensitivity: 1.0,
            smoothing: 0.5,
            bands: 32,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct ModeConfig {
    pub visual: String,
    pub fps: u32,
    /// Mode-specific overrides of the shared `[audio]` defaults. `None` means
    /// "inherit". `-1.0` is used as the "unset" sentinel (a real sensitivity is
    /// always >= 0, so -1 can never collide; NaN is avoided because the TOML
    /// encoder serialises it as `0.0`, which would be read back as a real,
    /// muting value).
    #[serde(default)]
    pub sensitivity: f32,
    #[serde(default)]
    pub smoothing: f32,
    #[serde(default)]
    pub bands: usize,
    /// Extra (mode-only) knobs — e.g. mini density, full zoom.
    #[serde(default)]
    pub extra: BTreeMap<String, f32>,
}

/// Sentinel for "inherit the shared default". `-1.0` (impossible for a real
/// sensitivity/smoothing, which are >= 0).
pub const INHERIT: f32 = -1.0;

impl Default for ModeConfig {
    fn default() -> Self {
        ModeConfig {
            visual: "bars".into(),
            fps: 60,
            sensitivity: INHERIT,
            smoothing: INHERIT,
            bands: 0, // 0 = inherit
            extra: BTreeMap::new(),
        }
    }
}

/// How the palette is chosen. `Auto` follows the Omarchy theme (light/dark +
/// accent); `Manual` uses the explicit colours below.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum PaletteSource {
    Auto,
    Manual,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Palette {
    pub source: PaletteSource,
    pub low: [f32; 3],
    pub high: [f32; 3],
    pub bg: [f32; 4],
    /// Background opacity, applied in auto mode (and as bg alpha in manual).
    pub opacity: f32,
}

impl Default for Palette {
    fn default() -> Self {
        Palette {
            source: PaletteSource::Auto,
            low: [0.15, 0.75, 0.95],
            high: [0.95, 0.25, 0.65],
            bg: [0.02, 0.02, 0.04, 1.0],
            opacity: 1.0,
        }
    }
}

impl Default for Config {
    fn default() -> Self {
        Config {
            audio: Audio::default(),
            // Default mode on first install is mini (menu bar only).
            desktop: ModeConfig {
                visual: "bars".into(),
                fps: 60,
                ..Default::default()
            },
            full: ModeConfig {
                visual: "wave".into(),
                fps: 0,
                extra: {
                    let mut m = BTreeMap::new();
                    // full_detail: how much room the bars use (1 = full, <1 = shorter).
                    m.insert("full_detail".into(), 1.0);
                    // full_quality: supersampling-ish factor for circular visuals.
                    m.insert("full_quality".into(), 1.5);
                    m
                },
                ..Default::default()
            },
            mini: ModeConfig {
                visual: "bars".into(),
                fps: 30,
                // mini renders denser: more bands + a bit more smoothing.
                bands: 48,
                smoothing: 0.6,
                extra: {
                    let mut m = BTreeMap::new();
                    m.insert("density".into(), 1.0);
                    // Gain + floor make the tiny menu-bar bars actually readable:
                    // gain amplifies quiet audio, floor keeps a minimum bar height.
                    m.insert("mini_gain".into(), 1.6);
                    m.insert("mini_floor".into(), 0.12);
                    m
                },
                ..Default::default()
            },
            palette: Palette::default(),
            visuals: BTreeMap::new(),
        }
    }
}

pub fn config_dir() -> PathBuf {
    let base = std::env::var("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
            PathBuf::from(std::env::var("HOME").unwrap_or_else(|_| "/tmp".into())).join(".config")
        });
    base.join("omaviz")
}

pub fn config_path() -> PathBuf {
    config_dir().join("config.toml")
}

impl Config {
    pub fn load_or_init() -> Result<Config> {
        let path = config_path();
        if !path.exists() {
            let cfg = Config::default();
            std::fs::create_dir_all(config_dir())?;
            std::fs::write(&path, toml::to_string_pretty(&cfg)?)?;
            return Ok(cfg);
        }
        let text = std::fs::read_to_string(&path)?;
        Ok(toml::from_str(&text)?)
    }

    pub fn save(&self) -> Result<()> {
        std::fs::create_dir_all(config_dir())?;
        // Write-then-rename so watchers never observe a half-written file.
        let tmp = config_path().with_extension("toml.tmp");
        std::fs::write(&tmp, toml::to_string_pretty(self)?)?;
        std::fs::rename(tmp, config_path())?;
        Ok(())
    }

    pub fn mode(&self, mode: Mode) -> &ModeConfig {
        match mode {
            Mode::Desktop => &self.desktop,
            Mode::Full => &self.full,
            Mode::Mini => &self.mini,
        }
    }

    pub fn mode_mut(&mut self, mode: Mode) -> &mut ModeConfig {
        match mode {
            Mode::Desktop => &mut self.desktop,
            Mode::Full => &mut self.full,
            Mode::Mini => &mut self.mini,
        }
    }

    /// Effective sensitivity for a mode: its override, else the shared default.
    pub fn sensitivity(&self, mode: Mode) -> f32 {
        let m = self.mode(mode);
        if m.sensitivity < 0.0 {
            self.audio.sensitivity
        } else {
            m.sensitivity
        }
    }

    /// Effective smoothing for a mode.
    pub fn smoothing(&self, mode: Mode) -> f32 {
        let m = self.mode(mode);
        if m.smoothing < 0.0 {
            self.audio.smoothing
        } else {
            m.smoothing
        }
    }

    /// Effective band count for a mode (0 means inherit the shared count).
    pub fn bands(&self, mode: Mode) -> usize {
        let m = self.mode(mode);
        if m.bands == 0 {
            self.audio.bands.max(1)
        } else {
            m.bands.max(1)
        }
    }

    /// Effective colours, resolving `auto` against the current Omarchy theme.
    pub fn resolved_palette(&self) -> ResolvedPalette {
        match self.palette.source {
            PaletteSource::Manual => ResolvedPalette {
                low: self.palette.low,
                high: self.palette.high,
                bg: self.palette.bg,
                is_light: false,
            },
            PaletteSource::Auto => {
                let t = crate::theme::detect();
                ResolvedPalette {
                    low: t.accent,
                    high: t.accent_secondary(),
                    bg: t.viz_background(self.palette.opacity),
                    is_light: t.is_light(),
                }
            }
        }
    }

    /// Value of a per-visual knob, falling back to the shader's declared default.
    pub fn visual_param(&self, visual: &str, param: &crate::visual::Param) -> f32 {
        self.visuals
            .get(visual)
            .and_then(|m| m.get(&param.name))
            .copied()
            .unwrap_or(param.default)
            .clamp(param.min, param.max)
    }

    pub fn set_visual_param(&mut self, visual: &str, name: &str, value: f32) {
        self.visuals
            .entry(visual.to_string())
            .or_default()
            .insert(name.to_string(), value);
    }

    /// Set the active visualization for ALL display modes at once (mini,
    /// desktop, full) — the visualization choice is shared; only per-display
    /// *fit* tweaks differ between modes.
    pub fn set_visual_all(&mut self, name: &str) {
        self.mini.visual = name.to_string();
        self.desktop.visual = name.to_string();
        self.full.visual = name.to_string();
    }

    /// Reset a single visualization's per-knob overrides back to the shader's
    /// declared defaults (in-memory; `save` persists).
    pub fn reset_visual(&mut self, name: &str) {
        self.visuals.remove(name);
    }
}

#[derive(Debug, Clone, Copy)]
pub struct ResolvedPalette {
    pub low: [f32; 3],
    pub high: [f32; 3],
    pub bg: [f32; 4],
    pub is_light: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Mode {
    Desktop,
    Full,
    Mini,
}

/// Polls config.toml's mtime and reloads when it changes.
///
/// Deliberately mtime polling rather than inotify: one `stat` every 500 ms is
/// far cheaper than an inotify thread per client, and config edits are rare.
pub struct Watcher {
    path: PathBuf,
    last: Option<SystemTime>,
    next_check: std::time::Instant,
    period: Duration,
}

impl Watcher {
    pub fn new() -> Watcher {
        let path = config_path();
        let last = std::fs::metadata(&path).and_then(|m| m.modified()).ok();
        Watcher {
            path,
            last,
            next_check: std::time::Instant::now(),
            period: Duration::from_millis(500),
        }
    }

    /// Returns the new config when the file changed since the last call.
    pub fn poll(&mut self) -> Option<Config> {
        let now = std::time::Instant::now();
        if now < self.next_check {
            return None;
        }
        self.next_check = now + self.period;

        let m = std::fs::metadata(&self.path)
            .and_then(|m| m.modified())
            .ok();
        if m == self.last {
            return None;
        }
        self.last = m;
        match Config::load_or_init() {
            Ok(c) => Some(c),
            Err(e) => {
                eprintln!("omaviz: config reload failed: {e:#}");
                None
            }
        }
    }
}

impl Default for Watcher {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_config_has_all_three_modes() {
        let c = Config::default();
        assert_eq!(c.mode(Mode::Mini).visual, "bars");
        assert_eq!(c.mode(Mode::Desktop).visual, "bars");
        assert_eq!(c.mode(Mode::Full).visual, "wave");
        assert!(c.audio.bands >= 16, "default band count should be reasonable");
    }

    #[test]
    fn mode_mut_and_mode_return_same_config() {
        let mut c = Config::default();
        c.mode_mut(Mode::Mini).sensitivity = 2.0;
        assert_eq!(c.mode(Mode::Mini).sensitivity, 2.0);
        assert_ne!(c.mode(Mode::Desktop).sensitivity, 2.0);
    }

    #[test]
    fn sensitivity_inherits_audio_default_when_negative() {
        let mut c = Config::default();
        c.mode_mut(Mode::Mini).sensitivity = -1.0;
        c.audio.sensitivity = 1.5;
        assert_eq!(c.sensitivity(Mode::Mini), 1.5);
        c.mode_mut(Mode::Full).sensitivity = 0.5;
        assert_eq!(c.sensitivity(Mode::Full), 0.5);
    }

    #[test]
    fn bands_inherits_audio_when_zero() {
        let mut c = Config::default();
        c.mode_mut(Mode::Desktop).bands = 0;
        c.audio.bands = 24;
        assert_eq!(c.bands(Mode::Desktop), 24);
        c.mode_mut(Mode::Desktop).bands = 8;
        assert_eq!(c.bands(Mode::Desktop), 8);
    }

    #[test]
    fn set_visual_all_updates_every_mode() {
        let mut c = Config::default();
        c.set_visual_all("fire");
        assert_eq!(c.mode(Mode::Mini).visual, "fire");
        assert_eq!(c.mode(Mode::Desktop).visual, "fire");
        assert_eq!(c.mode(Mode::Full).visual, "fire");
    }

    #[test]
    fn visual_param_uses_override_else_default_and_clamps() {
        let mut c = Config::default();
        let p = crate::visual::Param {
            name: "gain".into(),
            label: "Gain".into(),
            default: 1.0,
            min: 0.0,
            max: 2.0,
            boolean: false,
            help: String::new(),
        };
        assert_eq!(c.visual_param("bars", &p), 1.0);
        c.set_visual_param("bars", "gain", 1.5);
        assert_eq!(c.visual_param("bars", &p), 1.5);
        c.set_visual_param("bars", "gain", 9.0);
        assert_eq!(c.visual_param("bars", &p), 2.0);
    }

    #[test]
    fn reset_visual_clears_overrides() {
        let mut c = Config::default();
        c.set_visual_param("bars", "gain", 1.8);
        assert!(c.visuals.contains_key("bars"));
        c.reset_visual("bars");
        assert!(!c.visuals.contains_key("bars"));
    }

    #[test]
    fn per_mode_extra_defaults_exist_for_mini_fit() {
        let c = Config::default();
        assert!(c.mode(Mode::Mini).extra.contains_key("mini_gain"));
        assert!(c.mode(Mode::Mini).extra.contains_key("mini_floor"));
        assert!(c.mode(Mode::Full).extra.contains_key("full_detail"));
        assert!(c.mode(Mode::Full).extra.contains_key("full_quality"));
    }
}
