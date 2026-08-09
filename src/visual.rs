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

    out.sort_by(|a, b| a.name.cmp(&b.name));
    out
}

pub fn find(name: &str) -> Option<Visual> {
    discover().into_iter().find(|v| v.name == name)
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
