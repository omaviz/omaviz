//! Visualization registry: discovers `<name>.wgsl` shaders and their optional
//! `<name>.toml` parameter declarations.
//!
//! Declaring knobs in data (rather than compiling them in) is what keeps
//! "drop in a shader, no rebuild" working: the settings panel renders whatever
//! each visual declares, and the renderer feeds the values to the shader.
//!
//! Two kinds of knobs:
//!   * `params`     — per-visualization knobs (apply to the visual everywhere)
//!   * `extra_params` — mode-only tweaks (e.g. mini density, full zoom). These
//!     are stored in the mode's `extra` table, not in `visuals[...]`, so a
//!     change to mini's density doesn't leak into the desktop window.

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

/// Max knobs a visual may declare. Fixed so the uniform layout is stable.
pub const MAX_PARAMS: usize = 8;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Param {
    pub name: String,
    #[serde(default)]
    pub label: String,
    pub default: f32,
    #[serde(default)]
    pub min: f32,
    #[serde(default = "one")]
    pub max: f32,
    /// Rendered as a checkbox when true.
    #[serde(default)]
    pub boolean: bool,
    #[serde(default)]
    pub help: String,
}

fn one() -> f32 {
    1.0
}

impl Param {
    pub fn display_label(&self) -> &str {
        if self.label.is_empty() {
            &self.name
        } else {
            &self.label
        }
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
struct VisualManifest {
    #[serde(default)]
    label: String,
    #[serde(default)]
    description: String,
    #[serde(default)]
    params: Vec<Param>,
    /// Mode-only knobs (mini density, full zoom, …).
    #[serde(default)]
    extra_params: Vec<Param>,
}

#[derive(Debug, Clone)]
pub struct Visual {
    pub name: String,
    pub label: String,
    pub description: String,
    pub params: Vec<Param>,
    pub extra_params: Vec<Param>,
    pub path: PathBuf,
}

impl Visual {
    pub fn display_label(&self) -> &str {
        if self.label.is_empty() {
            &self.name
        } else {
            &self.label
        }
    }
}

/// Directory holding the shaders: user config first, then the source tree.
pub fn visuals_dir() -> PathBuf {
    let user = crate::config::config_dir().join("visuals");
    if user.is_dir() {
        return user;
    }
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("visuals")
}

/// Every visualization available, sorted by name. Files starting with `_`
/// are shared includes, not visuals.
pub fn discover() -> Vec<Visual> {
    let dir = visuals_dir();
    let mut out = Vec::new();
    let Ok(rd) = std::fs::read_dir(&dir) else {
        return out;
    };

    for e in rd.flatten() {
        let p = e.path();
        if p.extension().and_then(|s| s.to_str()) != Some("wgsl") {
            continue;
        }
        let Some(name) = p.file_stem().and_then(|s| s.to_str()) else {
            continue;
        };
        if name.starts_with('_') {
            continue;
        }

        let mut m = VisualManifest::default();
        let manifest = p.with_extension("toml");
        if let Ok(text) = std::fs::read_to_string(&manifest) {
            match toml::from_str::<VisualManifest>(&text) {
                Ok(parsed) => m = parsed,
                Err(e) => eprintln!("omaviz: bad manifest {}: {e}", manifest.display()),
            }
        }
        m.params.truncate(MAX_PARAMS);
        m.extra_params.truncate(MAX_PARAMS);

        out.push(Visual {
            name: name.to_string(),
            label: m.label,
            description: m.description,
            params: m.params,
            extra_params: m.extra_params,
            path: p,
        });
    }

    out.sort_by(|a, b| a.display_label().cmp(b.display_label()));
    out
}

pub fn find(name: &str) -> Option<Visual> {
    discover().into_iter().find(|v| v.name == name)
}

/// Rough classification used by the settings panel to surface the right
/// per-display *fit* knobs. Bar-style visuals need help on the tiny menu bar
/// (fill the small height); circular/disk visuals want room, so they shine on
/// full screen. This is heuristic — based on the visual name — so dropping in a
/// new shader just works without code changes.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum VisualKind {
    Bars,
    Circular,
    Other,
}

pub fn visual_kind(name: &str) -> VisualKind {
    let n = name.to_ascii_lowercase();
    if n.contains("bar") || n.contains("fire") || n.contains("wave") || n.contains("pulse") {
        VisualKind::Bars
    } else if n.contains("disk")
        || n.contains("ring")
        || n.contains("circ")
        || n.contains("spectro")
        || n.contains("sphere")
    {
        VisualKind::Circular
    } else {
        VisualKind::Other
    }
}

/// Full shader source: shared prelude + the visual's own fragment stage.
pub fn shader_source(v: &Visual) -> Result<String> {
    let dir = visuals_dir();
    let common = std::fs::read_to_string(dir.join("_common.wgsl"))
        .context("visuals/_common.wgsl is missing")?;
    let body = std::fs::read_to_string(&v.path)
        .with_context(|| format!("reading {}", v.path.display()))?;
    Ok(format!("{common}\n{body}"))
}

/// Resolve a visual name, falling back to the first available one so a bad
/// config entry never leaves a client with nothing to draw.
pub fn resolve_or_first(name: &str) -> Option<Visual> {
    if let Some(v) = find(name) {
        return Some(v);
    }
    let all = discover();
    if !all.is_empty() {
        eprintln!("omaviz: visual '{name}' not found, using '{}'", all[0].name);
    }
    all.into_iter().next()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn discover_returns_installed_visuals() {
        let vs = discover();
        assert!(!vs.is_empty(), "expected at least one shader in visuals/");
        // Required default visuals must be present.
        let names: Vec<&str> = vs.iter().map(|v| v.name.as_str()).collect();
        assert!(names.iter().any(|n| *n == "bars"), "bars missing");
        assert!(names.iter().any(|n| *n == "wave"), "wave missing");
    }

    #[test]
    fn discover_is_sorted_by_display_label() {
        let vs = discover();
        let labels: Vec<&str> = vs.iter().map(|v| v.display_label()).collect();
        let sorted = {
            let mut s = labels.clone();
            s.sort();
            s
        };
        assert_eq!(labels, sorted, "discover() must be sorted by display label");
    }

    #[test]
    fn find_returns_exact_match() {
        let v = find("bars");
        assert!(v.is_some());
        assert_eq!(v.unwrap().name, "bars");
        assert!(find("does-not-exist").is_none());
    }

    #[test]
    fn resolve_or_first_falls_back() {
        assert!(resolve_or_first("nope").is_some());
        assert_eq!(resolve_or_first("bars").unwrap().name, "bars");
    }

    #[test]
    fn visual_kind_classifies_names() {
        assert_eq!(visual_kind("bars"), VisualKind::Bars);
        assert_eq!(visual_kind("fire"), VisualKind::Bars);
        assert_eq!(visual_kind("disk-spectro"), VisualKind::Circular);
        assert_eq!(visual_kind("ring"), VisualKind::Circular);
        assert_eq!(visual_kind("totally-unknown"), VisualKind::Other);
    }

    #[test]
    fn display_label_falls_back_to_name() {
        let v = Visual {
            name: "myviz".into(),
            label: String::new(),
            description: String::new(),
            params: vec![],
            extra_params: vec![],
            path: std::path::PathBuf::from("x"),
        };
        assert_eq!(v.display_label(), "myviz");
    }
}
