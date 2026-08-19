//! Audio source backends.
//!
//! This build compiles PipeWire plus two synthetic backends for deterministic
//! offline testing (engine lane #11, no plugin/QML changes):
//!   - `gen[=mode[:param=value;...]]`  built-in tone/noise/sweep generator
//!   - `file=<path>[:fps=N][:loop]`    replays a recorded spectrum stream
//! The plugin still spawns the engine with `--source auto`; all backend
//! selection is internal. Additional backends (pulse/jack/alsa) are added here
//! later WITHOUT touching the plugin.

pub mod pipewire;
pub mod gen;
pub mod file;

use crate::dsp::AudioChunk;

/// A single source event delivered to the engine main loop.
///
/// - `Chunk`  carries raw audio to be analyzed (pipewire / gen).
/// - `Frame`  carries a pre-computed spectrum to emit verbatim (file replay).
/// - `Exit`   asks the engine to terminate (file replay reaching end-of-file).
pub enum SourceEvent {
    Chunk(AudioChunk),
    Frame {
        bands: Vec<f32>,
        energy: f32,
        beat: f32,
        silent: bool,
        source: String,
    },
    Exit,
}

pub type SourceEventReceiver = std::sync::mpsc::Receiver<SourceEvent>;

/// Resolve a requested source flag to a concrete backend name.
/// `auto`/`""` fall through to the default (PipeWire). `gen*`, `file*` keep
/// their prefix name. Returns Err for unsupported/unknown names.
pub fn resolve(requested: &str) -> anyhow::Result<String> {
    match requested {
        "pipewire" | "auto" | "" => Ok("pipewire".to_string()),
        s if s.starts_with("gen") => Ok("gen".to_string()),
        s if s.starts_with("file") => Ok("file".to_string()),
        other => anyhow::bail!(
            "unsupported audio source: {other} (available: auto, pipewire, gen, file)"
        ),
    }
}

/// Spawn the requested backend and return a channel of source events.
/// The plugin always passes `auto`. Synthetic backends (gen/file) run without
/// any audio server; pipewire runs the capture thread.
pub fn spawn(requested: &str) -> anyhow::Result<SourceEventReceiver> {
    let (tx, rx) = std::sync::mpsc::channel::<SourceEvent>();
    if requested.is_empty() || requested == "auto" || requested == "pipewire" {
        // Forward PipeWire's raw chunks as Chunk events. (PipeWire never signals
        // Exit — capture runs until the process exits.)
        let prx = pipewire::spawn()?;
        std::thread::spawn(move || {
            for chunk in prx {
                if tx.send(SourceEvent::Chunk(chunk)).is_err() {
                    return;
                }
            }
        });
    } else if let Some(spec) = requested.strip_prefix("gen") {
        gen::spawn(spec, tx)?;
    } else if let Some(spec) = requested.strip_prefix("file") {
        file::spawn(spec, tx)?;
    } else {
        anyhow::bail!(
            "unsupported audio source: {requested} (available: auto, pipewire, gen, file)"
        );
    }
    Ok(rx)
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
    fn gen_resolves_to_gen() {
        assert_eq!(resolve("gen").unwrap(), "gen");
        assert_eq!(resolve("gen=tone").unwrap(), "gen");
        assert_eq!(resolve("gen=noise:freq=10").unwrap(), "gen");
    }

    #[test]
    fn file_resolves_to_file() {
        assert_eq!(resolve("file=/tmp/rec.txt").unwrap(), "file");
        assert_eq!(resolve("file=/tmp/rec.txt:fps=30:loop").unwrap(), "file");
    }

    #[test]
    fn unknown_source_errors() {
        assert!(resolve("alsa").is_err());
        assert!(resolve("bogus").is_err());
        assert!(resolve("pulse").is_err());
    }

    #[test]
    fn spawn_auto_succeeds_via_pipewire() {
        // Does not require a running PipeWire server — spawn() only launches the
        // capture thread (which will error later on connect, not at spawn).
        assert!(spawn("auto").is_ok());
        assert!(spawn("").is_ok());
    }

    #[test]
    fn spawn_gen_succeeds() {
        assert!(spawn("gen=tone").is_ok());
        assert!(spawn("gen=noise").is_ok());
        assert!(spawn("gen=sweep:rate=1200").is_ok());
    }

    #[test]
    fn spawn_gen_unknown_mode_errors_at_spawn() {
        let (tx, _rx) = std::sync::mpsc::channel();
        assert!(gen::spawn("=bogus", tx).is_err());
    }

    #[test]
    fn spawn_file_without_path_errors() {
        let (tx, _rx) = std::sync::mpsc::channel();
        assert!(file::spawn("", tx.clone()).is_err());
        assert!(file::spawn("=", tx).is_err());
    }
}
