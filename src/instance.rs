//! Single-instance guards.
//!
//! Each windowed mode holds an exclusive flock on a runtime file. A second
//! launch fails to take the lock, so instead of spawning a duplicate window it
//! asks the compositor to focus the existing one (issue #1).

use anyhow::Result;
use std::fs::{File, OpenOptions};
use std::os::fd::AsRawFd;
use std::path::PathBuf;

/// Identifies a distinct omaviz entity that needs a single instance.
/// The daemon and the desktop window are DIFFERENT entities — the daemon must
/// not hold the desktop window's lock, or `omaviz desktop` would always see
/// "already running" and never open.
#[derive(Clone, Copy)]
pub enum WindowKind {
    Daemon,
    Desktop,
    Full,
    Settings,
}

impl WindowKind {
    fn lock_name(self) -> &'static str {
        match self {
            WindowKind::Daemon => "daemon",
            WindowKind::Desktop => "desktop",
            WindowKind::Full => "full",
            WindowKind::Settings => "settings",
        }
    }
    fn title(self) -> &'static str {
        match self {
            WindowKind::Daemon => "omaviz daemon",
            WindowKind::Desktop => "omaviz",
            WindowKind::Full => "omaviz fullscreen",
            WindowKind::Settings => "omaviz settings",
        }
    }
}

pub struct SingleInstance {
    _file: File,
    path: PathBuf,
}

fn lock_path(name: &str) -> PathBuf {
    let base = std::env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/tmp".into());
    PathBuf::from(base).join(format!("omaviz-{name}.lock"))
}

/// Try to become the only instance of `kind`.
/// Returns `Ok(None)` when another instance already holds the lock.
pub fn acquire(kind: WindowKind) -> Result<Option<SingleInstance>> {
    let path = lock_path(kind.lock_name());
    let file = OpenOptions::new()
        .create(true)
        .write(true)
        .truncate(false)
        .open(&path)?;

    // LOCK_EX | LOCK_NB — non-blocking exclusive lock, released on process exit.
    let rc = unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) };
    if rc != 0 {
        let err = std::io::Error::last_os_error();
        if err.kind() == std::io::ErrorKind::WouldBlock {
            return Ok(None);
        }
        return Err(err.into());
    }
    Ok(Some(SingleInstance { _file: file, path }))
}

impl Drop for SingleInstance {
    fn drop(&mut self) {
        // Lock releases with the fd; remove the file so it doesn't accumulate.
        let _ = std::fs::remove_file(&self.path);
    }
}

/// Ask Hyprland to focus an already-running omaviz window of `kind`.
pub fn focus_existing(kind: WindowKind) {
    let _ = std::process::Command::new("hyprctl")
        .args([
            "dispatch",
            "focuswindow",
            &format!("title:^{}$", kind.title()),
        ])
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status();
}
