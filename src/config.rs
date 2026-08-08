//! TOML config, hot-reloaded by daemon and clients.

use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Config {
    pub bands: usize,
    pub sensitivity: f32,
    pub smoothing: f32,
    pub desktop: ModeConfig,
    pub full: ModeConfig,
    pub mini: ModeConfig,
    pub palette: Palette,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct ModeConfig {
    /// Visualization name; must match a file in visuals/<name>.wgsl
    pub visual: String,
    pub fps: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Palette {
    /// RGB 0..1
    pub low: [f32; 3],
    pub high: [f32; 3],
    pub bg: [f32; 4],
}

impl Default for Config {
    fn default() -> Self {
        Config {
            bands: 32,
            sensitivity: 1.0,
            smoothing: 0.5,
            desktop: ModeConfig {
                visual: "bars".into(),
                fps: 60,
            },
            full: ModeConfig {
                visual: "wave".into(),
                fps: 0, // 0 = monitor refresh
            },
            mini: ModeConfig {
                visual: "bars".into(),
                fps: 30,
            },
            palette: Palette::default(),
        }
    }
}

impl Default for ModeConfig {
    fn default() -> Self {
        ModeConfig {
            visual: "bars".into(),
            fps: 60,
        }
    }
}

impl Default for Palette {
    fn default() -> Self {
        Palette {
            low: [0.15, 0.75, 0.95],
            high: [0.95, 0.25, 0.65],
            bg: [0.02, 0.02, 0.04, 1.0],
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
    /// Load config, writing defaults on first run.
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
        std::fs::write(config_path(), toml::to_string_pretty(self)?)?;
        Ok(())
    }

    pub fn mode(&self, mode: Mode) -> &ModeConfig {
        match mode {
            Mode::Desktop => &self.desktop,
            Mode::Full => &self.full,
            Mode::Mini => &self.mini,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Mode {
    Desktop,
    Full,
    Mini,
}
