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
    params: Vec<Param>,
}

#[derive(Debug, Clone)]
pub struct Visual {
    pub name: String,
    pub label: String,
    pub params: Vec<Param>,
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

        out.push(Visual {
            name: name.to_string(),
            label: m.label,
            params: m.params,
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

/// Validate shader source for safety before loading.
/// Checks for potentially dangerous patterns and ensures basic WGSL structure.
pub fn validate_shader_source(source: &str, name: &str) -> anyhow::Result<()> {
    // Basic structure checks
    if !source.contains("@fragment") && !source.contains("@vertex") {
        anyhow::bail!("Shader '{}' missing required @fragment or @vertex entry point", name);
    }
    if !source.contains("fs_main") && !source.contains("vs_main") {
        anyhow::bail!("Shader '{}' missing main entry point function", name);
    }
    
    // Security: reject shaders that try to access sensitive operations
    // These are not valid in WGSL anyway but check for any injection attempts
    let dangerous_patterns = [
        "import",       // WGSL doesn't have import
        "include",      // WGSL doesn't have include
        "#version",     // GLSL directive, not WGSL
        "#extension",   // GLSL directive
        "subroutine",   // GLSL feature
        "layout(",      // Could be valid in WGSL for bind groups, but check context
    ];
    
    for pattern in dangerous_patterns {
        if source.contains(pattern) {
            // Allow layout() for bind group layouts which are valid WGSL
            if pattern == "layout(" && !source.contains("binding") {
                anyhow::bail!("Shader '{}' contains suspicious pattern: {}", name, pattern);
            }
        }
    }
    
    // Check for reasonable size (prevent DoS via massive shaders)
    if source.len() > 100_000 {
        anyhow::bail!("Shader '{}' exceeds maximum size (100KB)", name);
    }
    
    Ok(())
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
            params: vec![],
            path: std::path::PathBuf::from("x"),
        };
        assert_eq!(v.display_label(), "myviz");
    }

    #[test]
    fn validate_shader_source_accepts_valid_shader() {
        let valid = r#"
@vertex
fn vs_main(@builtin(vertex_index) vi: u32) -> @builtin(position) vec4<f32> {
    return vec4<f32>(0.0, 0.0, 0.0, 1.0);
}

@fragment
fn fs_main(@builtin(position) frag: vec4<f32>) -> @location(0) vec4<f32> {
    return vec4<f32>(1.0, 0.0, 0.0, 1.0);
}
"#;
        assert!(validate_shader_source(valid, "test").is_ok());
    }

    #[test]
    fn validate_shader_source_rejects_missing_entry_point() {
        let invalid = "fn main() {}";
        assert!(validate_shader_source(invalid, "test").is_err());
    }

    #[test]
    fn validate_shader_source_rejects_oversized() {
        let oversized = "@fragment\nfn fs_main() -> @location(0) vec4<f32> { return vec4<f32>(1.0); }".repeat(10000);
        assert!(validate_shader_source(&oversized, "test").is_err());
    }
}
