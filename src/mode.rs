//! Mode / on-screen state machine for omaviz.
//!
//! Two live states:
//! - `Mini`    -> visualization shown as bars in the waybar module, desktop window closed.
//! - `Desktop` -> visualization shown in the floating desktop window, waybar module shows icon-only.
//! `Off` is not a mode in the menu but an orthogonal "paused" flag: the daemon keeps
//! running and the mini module stays in the bar (dimmed) but audio capture is suspended.
//!
//! `Exit` (Quit) is a hard teardown: close window, stop daemon, remove from waybar.

use crate::ipc::Frame;
use std::io::Write;
use std::process::Command;
use std::sync::Mutex;

#[derive(Clone, Copy, Debug, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Mode {
    Off,
    Mini,
    Desktop,
}

impl Mode {
    pub fn parse(s: &str) -> Option<Mode> {
        match s.trim().to_ascii_lowercase().as_str() {
            "off" => Some(Mode::Off),
            "mini" | "mini+desktop" | "mini+full" => Some(Mode::Mini),
            "desktop" | "full" => Some(Mode::Desktop),
            _ => None,
        }
    }

    /// Whether this state wants the desktop window open.
    pub fn shows_desktop(self) -> bool {
        matches!(self, Mode::Desktop)
    }

    /// Whether the desktop window is currently the active display (so the mini
    /// module should render *dimmed* rather than live bars).
    pub fn desktop_active(self) -> bool {
        matches!(self, Mode::Desktop)
    }

    /// Whether the module should render dimmed (no live visualization): either
    /// the desktop window is showing it, or we're paused (Off).
    pub fn dimmed(self) -> bool {
        matches!(self, Mode::Desktop | Mode::Off)
    }
}

impl std::fmt::Display for Mode {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let s = match self {
            Mode::Off => "off",
            Mode::Mini => "mini",
            Mode::Desktop => "desktop",
        };
        f.write_str(s)
    }
}

/// Orthogonal "paused" flag (set by `Off`, cleared by any mode select / toggle).
static PAUSED: Mutex<bool> = Mutex::new(false);

pub fn is_paused() -> bool {
    *PAUSED.lock().unwrap()
}

pub fn set_paused(p: bool) {
    *PAUSED.lock().unwrap() = p;
}

const MODE_FILE: &str = "mode";

pub fn read_raw() -> Option<String> {
    let mut p = dirs().ok()?;
    p.push(MODE_FILE);
    std::fs::read_to_string(p).ok().map(|s| s.trim().to_string())
}

pub fn current() -> Mode {
    read_raw()
        .as_deref()
        .and_then(Mode::parse)
        .unwrap_or(Mode::Mini)
}

/// Persistent module "exited" flag: when set, the mini module should render
/// nothing (the user chose Exit and removed it from the bar).
const EXITED_FILE: &str = "exited";

fn exited_path() -> Option<std::path::PathBuf> {
    dirs().ok().map(|mut p| {
        p.push(EXITED_FILE);
        p
    })
}

pub fn is_exited() -> bool {
    exited_path().map(|p| p.exists()).unwrap_or(false)
}

pub fn set_exited(v: bool) {
    if let Some(p) = exited_path() {
        if v {
            let _ = std::fs::write(&p, "1");
        } else if p.exists() {
            let _ = std::fs::remove_file(&p);
        }
    }
}

fn dirs() -> Result<std::path::PathBuf, ()> {
    let base = std::env::var("XDG_RUNTIME_DIR")
        .map(std::path::PathBuf::from)
        .or_else(|_| -> Result<std::path::PathBuf, ()> {
            let uid = unsafe { libc::getuid() };
            if uid == 0 {
                Ok(std::path::PathBuf::from("/run"))
            } else {
                Ok(std::path::PathBuf::from(format!("/run/user/{}", uid)))
            }
        });
    let mut p = base.map_err(|_| ())?;
    p.push("omaviz");
    std::fs::create_dir_all(&p).map_err(|_| ())?;
    Ok(p)
}

fn write_mode(m: Mode) {
    if let Some(mut p) = dirs().ok() {
        p.push(MODE_FILE);
        if let Ok(mut f) = std::fs::File::create(&p) {
            let _ = f.write_all(m.to_string().as_bytes());
        }
    }
}

/// Apply a mode: write it, and start/stop the desktop window accordingly.
///
/// NOTE: this does NOT reload waybar. The mini client polls the mode file
/// every frame, so bars update live (dimmed when the desktop window is open,
/// live when closed) without a waybar config reload — avoiding the visual
/// "jump" a reload causes.
pub fn apply(m: Mode) {
    // Selecting any mode clears the paused + exited flags.
    set_paused(false);
    set_exited(false);

    let was_desktop = current().shows_desktop();
    write_mode(m);

    match m {
        Mode::Off => {
            // Pause audio capture but keep daemon + mini module (dimmed).
            set_paused(true);
            stop_desktop();
        }
        Mode::Mini => {
            if was_desktop {
                stop_desktop();
            }
        }
        Mode::Desktop => {
            if !was_desktop {
                spawn_desktop();
            }
        }
    }
}

/// Toggle between Mini and Desktop (the left-click behavior).
pub fn toggle() {
    if is_exited() {
        return;
    }
    match current() {
        Mode::Desktop => apply(Mode::Mini),
        _ => apply(Mode::Desktop),
    }
}

/// Off button: pause + close desktop, keep mini module visible (dimmed).
pub fn off() {
    set_exited(false);
    apply(Mode::Off);
}

/// Quit (Exit menu item): close desktop, stop daemon, remove from waybar.
pub fn quit() {
    set_exited(true);
    stop_desktop();
    // Remove the waybar module and reload so it disappears from the bar.
    remove_from_waybar();
    refresh_waybar();
    // Stop the daemon (and thus the whole app).
    stop_daemon();
}

/// Called by the desktop window when the user closes it: fall back to Mini.
pub fn window_closed() {
    // Only fall back if we're currently in Desktop; otherwise leave as-is.
    if current().shows_desktop() && !is_paused() {
        write_mode(Mode::Mini);
        // No waybar reload needed: the mini client polls this file each frame.
    }
}

fn spawn_desktop() {
    // Launch the desktop window as a separate process (singleton-guarded).
    let _ = Command::new(omaviz_bin())
        .arg("desktop")
        .spawn();
}

fn stop_desktop() {
    // Close any running desktop/full window process. Target ONLY the window
    // clients (not `omaviz quit`/daemon) so we don't kill our own process.
    let _ = Command::new("pkill")
        .args(["-f", "omaviz desktop"])
        .status();
    let _ = Command::new("pkill")
        .args(["-f", "omaviz full"])
        .status();
}

fn omaviz_bin() -> String {
    // Prefer the installed binary on PATH; fall back to the local build.
    if let Ok(out) = Command::new("which").arg("omaviz").output() {
        if out.status.success() {
            let s = String::from_utf8_lossy(&out.stdout).trim().to_string();
            if !s.is_empty() {
                return s;
            }
        }
    }
    "omaviz".to_string()
}

fn stop_daemon() {
    // Stop the user service if it is how omaviz is launched; otherwise kill the daemon.
    if Command::new("systemctl")
        .args(["--user", "is-active", "--quiet", "omaviz.service"])
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
    {
        let _ = Command::new("systemctl").args(["--user", "stop", "omaviz.service"]).status();
    } else {
        let _ = Command::new("pkill").args(["-x", "omaviz"]).status();
    }
}

pub fn refresh_waybar() {
    // Signal waybar to reload its config so module changes take effect.
    let _ = Command::new("pkill").args(["-USR2", "waybar"]).status();
}

fn remove_from_waybar() {
    // Strip the custom/omaviz module from the waybar config so it disappears
    // from the bar after Exit. The install splice logic lives in install.sh;
    // this is the runtime counterpart. We do brace-aware removal (the module
    // object contains nested braces from the menu-actions block).
    let cfg = std::env::var("XDG_CONFIG_HOME")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|_| {
            std::path::PathBuf::from(std::env::var("HOME").unwrap_or_default()).join(".config")
        })
        .join("waybar/config.jsonc");
    if !cfg.exists() {
        return;
    }
    let Ok(mut s) = std::fs::read_to_string(&cfg) else { return };

    // 1) Remove the reference in a "modules-*" array: "custom/omaviz",
    s = s.replace("\"custom/omaviz\",", "");

    // 2) Remove the module definition object (brace-aware), plus the trailing
    //    comma and the leading newline+indent so no dangling punctuation remains.
    let needle = "\"custom/omaviz\":";
    if let Some(start) = s.find(needle) {
        if let Some(brace) = s[start..].find('{') {
            let open = start + brace;
            let mut depth = 0i32;
            let mut close = None;
            for (i, c) in s[open..].char_indices() {
                match c {
                    '{' => depth += 1,
                    '}' => {
                        depth -= 1;
                        if depth == 0 {
                            close = Some(open + i);
                            break;
                        }
                    }
                    _ => {}
                }
            }
            if let Some(close) = close {
                // End just past the closing brace.
                let mut end = close + 1;
                // Consume a trailing comma if present.
                while end < s.len() && (s.as_bytes()[end] == b' ' || s.as_bytes()[end] == b'\t') {
                    end += 1;
                }
                if end < s.len() && s.as_bytes()[end] == b',' {
                    end += 1;
                }
                // Trim leading newline + indentation before the object.
                let mut obj_start = start;
                while obj_start > 0 && (s.as_bytes()[obj_start - 1] == b'\n'
                    || s.as_bytes()[obj_start - 1] == b' '
                    || s.as_bytes()[obj_start - 1] == b'\t')
                {
                    obj_start -= 1;
                }
                s.drain(obj_start..end);
            }
        }
    }
    let _ = std::fs::write(&cfg, &s);
    let _ = std::process::Command::new("pkill").args(["-SIGUSR2", "waybar"]).status();
}

/// Re-add the custom/omaviz module to the waybar config (used by `omaviz
/// start` after an Exit removed it). Mirrors install.sh: regenerate the menu
/// XML and splice the module with the absolute binary path.
pub fn add_waybar_module() {
    let cfg_home = std::env::var("XDG_CONFIG_HOME")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|_| {
            std::path::PathBuf::from(std::env::var("HOME").unwrap_or_default()).join(".config")
        });
    let wb_cfg = cfg_home.join("waybar/config.jsonc");
    if !wb_cfg.exists() {
        return;
    }
    let bin = omaviz_bin();
    // Right-click pops the interactive popup (`omaviz menu` -> walker --dmenu).
    // We deliberately do NOT use waybar's `menu-file` (GtkBuilder XML): in
    // waybar 0.15 that path triggers a GTK assertion crash. The popup is the
    // reliable approach.
    let module = format!(
        "  \"custom/omaviz\": {{\n    \"exec\": \"{bin} mini --width 18\",\n    \"return-type\": \"json\",\n    \"format\": \"{{}}\",\n    \"tooltip\": true,\n    \"escape\": false,\n    \"on-click\": \"{bin} toggle\",\n    \"on-click-right\": \"{bin} menu\",\n    \"exec-on-event\": false,\n    \"on-scroll-up\": \"{bin} sensitivity +0.1\",\n    \"on-scroll-down\": \"{bin} sensitivity -0.1\"\n  }},\n"
    );

    let Ok(s) = std::fs::read_to_string(&wb_cfg) else { return };
    // Already present? Nothing to do.
    if s.contains("\"custom/omaviz\":") {
        let _ = std::process::Command::new("pkill").args(["-SIGUSR2", "waybar"]).status();
        return;
    }
    let mut out = String::with_capacity(s.len() + module.len() + 64);
    // 1) Add the module reference into the first modules-* array.
    let mut inserted_ref = false;
    if let Some(m) = s.find("\"modules-right\"") {
        if let Some(b) = s[m..].find('[') {
            let at = m + b + 1;
            out.push_str(&s[..at]);
            out.push_str("\n    \"custom/omaviz\",");
            out.push_str(&s[at..]);
            inserted_ref = true;
        }
    }
    if !inserted_ref {
        for key in ["modules-center", "modules-left"] {
            if let Some(m) = s.find(key) {
                if let Some(b) = s[m..].find('[') {
                    let at = m + b + 1;
                    out.push_str(&s[..at]);
                    out.push_str("\n    \"custom/omaviz\",");
                    out.push_str(&s[at..]);
                    inserted_ref = true;
                    break;
                }
            }
        }
    }
    if !inserted_ref {
        out.push_str(&s);
    }
    // 2) Prepend the module object right after the top-level '{'.
    let body = if inserted_ref { out } else { s };
    let final_out = if let Some(b) = body.find('{') {
        let at = b + 1;
        let mut r = String::with_capacity(body.len() + module.len());
        r.push_str(&body[..at]);
        r.push('\n');
        r.push_str(&module);
        r.push_str(&body[at..]);
        r
    } else {
        body
    };
    let _ = std::fs::write(&wb_cfg, final_out);
    let _ = std::process::Command::new("pkill").args(["-SIGUSR2", "waybar"]).status();
}

/// Background frame pump for the mini client: applies paused + mode filtering
/// on top of the raw daemon frame.
pub fn decorate(frame: &Frame) -> Frame {
    let mut f = frame.clone();
    if is_paused() {
        // Keep last band shape but zero energy so it renders dimmed.
        f.silent = true;
    }
    f
}
