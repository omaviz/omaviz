//! Display-mode state machine (off / mini / desktop / mini+desktop).
//!
//! State lives in one small file so the waybar menu, the CLI and the settings
//! panel all agree. Changing it spawns or kills the desktop window; the mini
//! module reads it to decide whether to draw anything.

use anyhow::Result;
use std::path::PathBuf;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DisplayMode {
    Off,
    Mini,
    Desktop,
    MiniDesktop,
}

impl DisplayMode {
    pub fn as_str(self) -> &'static str {
        match self {
            DisplayMode::Off => "off",
            DisplayMode::Mini => "mini",
            DisplayMode::Desktop => "desktop",
            DisplayMode::MiniDesktop => "mini+desktop",
        }
    }

    pub fn parse(s: &str) -> Option<DisplayMode> {
        match s.trim() {
            "off" => Some(DisplayMode::Off),
            "mini" => Some(DisplayMode::Mini),
            "desktop" => Some(DisplayMode::Desktop),
            "mini+desktop" | "both" => Some(DisplayMode::MiniDesktop),
            _ => None,
        }
    }

    pub fn shows_mini(self) -> bool {
        matches!(self, DisplayMode::Mini | DisplayMode::MiniDesktop)
    }

    pub fn shows_desktop(self) -> bool {
        matches!(self, DisplayMode::Desktop | DisplayMode::MiniDesktop)
    }
}

pub fn state_path() -> PathBuf {
    let base = std::env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/tmp".into());
    PathBuf::from(base).join("omaviz.mode")
}

pub fn get() -> DisplayMode {
    std::fs::read_to_string(state_path())
        .ok()
        .and_then(|s| DisplayMode::parse(&s))
        .unwrap_or(DisplayMode::Mini)
}

pub fn set(m: DisplayMode) -> Result<()> {
    std::fs::write(state_path(), m.as_str())?;
    Ok(())
}

fn desktop_running() -> bool {
    // acquire returns None when another instance already holds the lock.
    matches!(
        crate::instance::acquire(crate::instance::WindowKind::Desktop),
        Ok(None)
    )
}

fn spawn_desktop() {
    let exe = std::env::current_exe().unwrap_or_else(|_| "omaviz".into());
    let _ = std::process::Command::new(exe)
        .arg("desktop")
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .spawn();
}

fn kill_desktop() {
    // The desktop client watches the mode file and exits on its own; this is
    // the fallback for a client that predates that or is wedged.
    let _ = std::process::Command::new("pkill")
        .args(["-f", "omaviz desktop"])
        .status();
}

/// Apply a mode: start or stop the desktop window to match.
pub fn apply(m: DisplayMode) -> Result<()> {
    set(m)?;
    if m.shows_desktop() {
        if !desktop_running() {
            spawn_desktop();
        }
    } else if desktop_running() {
        kill_desktop();
    }
    Ok(())
}

/// Toggle the desktop window on/off, preserving whether mini is shown.
pub fn toggle_desktop() -> Result<DisplayMode> {
    let cur = get();
    let next = match cur {
        DisplayMode::Off => DisplayMode::Desktop,
        DisplayMode::Mini => DisplayMode::MiniDesktop,
        DisplayMode::Desktop => DisplayMode::Off,
        DisplayMode::MiniDesktop => DisplayMode::Mini,
    };
    apply(next)?;
    Ok(next)
}
