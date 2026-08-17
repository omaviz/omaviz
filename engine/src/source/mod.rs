//! Audio source backends.
//!
//! v7 ships PipeWire only. The plugin spawns the engine with `--source
//! auto`; `resolve()` maps that to a concrete backend name. Additional backends
//! (pulse/jack/alsa/file) are added here later WITHOUT touching the plugin.

pub mod pipewire;

/// Resolve a requested source flag to a concrete backend name.
/// `auto`/`""` fall through to the default (PipeWire, the only compiled backend
/// in v7). Returns Err for unsupported/unknown names.
pub fn resolve(requested: &str) -> anyhow::Result<String> {
    match requested {
        "pipewire" | "auto" | "" => Ok("pipewire".to_string()),
        other => anyhow::bail!(
            "unsupported audio source: {other} (available: pipewire)"
        ),
    }
}

/// Spawn the requested backend. The plugin always passes `auto`.
pub fn spawn(requested: &str) -> anyhow::Result<std::sync::mpsc::Receiver<crate::dsp::AudioChunk>> {
    let name = resolve(requested)?;
    match name.as_str() {
        "pipewire" => pipewire::spawn(),
        _ => anyhow::bail!("backend {name} not compiled in"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn auto_resolves_to_pipewire() {
        assert_eq!(resolve("auto").unwrap(), "pipewire");
    }

    #[test]
    fn empty_resolves_to_pipewire() {
        assert_eq!(resolve("").unwrap(), "pipewire");
    }

    #[test]
    fn explicit_pipewire_resolves() {
        assert_eq!(resolve("pipewire").unwrap(), "pipewire");
    }

    #[test]
    fn unknown_source_errors() {
        assert!(resolve("alsa").is_err());
        assert!(resolve("bogus").is_err());
    }

    #[test]
    fn spawn_auto_succeeds_via_pipewire() {
        // Does not require a running PipeWire server — spawn() only launches the
        // capture thread (which will error later on connect, not at spawn).
        assert!(spawn("auto").is_ok());
        assert!(spawn("").is_ok());
    }
}
