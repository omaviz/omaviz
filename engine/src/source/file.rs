//! File/loopback source backend (engine lane #11): replays a recorded
//! spectrum stream. The harness records the engine's own stdout
//! (`{"bands":[..],"energy":f,"beat":f,"silent":b,"source":".."}` lines) and
//! replays it verbatim, so the desktop window gets a deterministic,
//! reproducible signal for screenshots — no real audio required.
//!
//! CLI grammar (text after the `file` prefix):
//!   --source file=<path>[:fps=N][:loop]
//!     <path>  recording file, one JSON frame per line (the engine's stdout)
//!     fps     frames per second to replay at (default 60)
//!     loop    restart from the beginning when the file ends (never exits)
//! When the file is exhausted without `loop`, the backend sends a single
//! SourceEvent::Exit so the engine terminates cleanly.

use crate::source::SourceEvent;
use anyhow::{bail, Result};
use std::sync::mpsc::Sender;

/// Spawn the file-replay thread. Returns once launched; errors only if the path
/// is missing/empty or the file cannot be read or contains no valid frames.
pub fn spawn(spec: &str, tx: Sender<SourceEvent>) -> Result<()> {
    let spec = spec.strip_prefix('=').unwrap_or(spec);
    let mut parts = spec.split(':');
    let path = parts.next().unwrap_or("").to_string();
    if path.is_empty() {
        bail!("file source requires a path, e.g. --source file=/tmp/rec.jsonl");
    }
    let mut fps = 60.0f32;
    let mut loop_file = false;
    for p in parts {
        if p == "loop" {
            loop_file = true;
        } else if let Some(v) = p.strip_prefix("fps=") {
            if let Ok(f) = v.parse::<f32>() {
                if f > 0.0 {
                    fps = f;
                }
            }
        }
    }
    let content = std::fs::read_to_string(&path)
        .map_err(|e| anyhow::anyhow!("cannot read source file {path}: {e}"))?;
    let frames = parse_frames(&content);
    if frames.is_empty() {
        bail!("source file {path} contained no valid frames");
    }
    std::thread::spawn(move || run(tx, frames, fps, loop_file));
    Ok(())
}

pub(crate) struct FrameData {
    pub bands: Vec<f32>,
    pub energy: f32,
    pub beat: f32,
    pub silent: bool,
}

fn run(tx: Sender<SourceEvent>, frames: Vec<FrameData>, fps: f32, loop_file: bool) {
    let delay = std::time::Duration::from_secs_f32(1.0 / fps.max(1.0));
    loop {
        for f in &frames {
            let ev = SourceEvent::Frame {
                bands: f.bands.clone(),
                energy: f.energy,
                beat: f.beat,
                silent: f.silent,
                source: "file".to_string(),
            };
            if tx.send(ev).is_err() {
                return; // consumer gone
            }
            std::thread::sleep(delay);
        }
        if !loop_file {
            let _ = tx.send(SourceEvent::Exit);
            return;
        }
    }
}

/// Parse a recording's text (one JSON frame per line) into FrameData.
pub(crate) fn parse_frames(content: &str) -> Vec<FrameData> {
    let mut out = Vec::new();
    for line in content.lines() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        if let Some(f) = parse_frame_line(line) {
            out.push(f);
        }
    }
    out
}

fn parse_frame_line(line: &str) -> Option<FrameData> {
    let v: serde_json::Value = serde_json::from_str(line).ok()?;
    let bands_val = v.get("bands")?.as_array()?;
    let mut bands = Vec::with_capacity(bands_val.len());
    for b in bands_val {
        bands.push(b.as_f64()? as f32);
    }
    let energy = v.get("energy").and_then(|x| x.as_f64()).unwrap_or(0.0) as f32;
    let beat = v.get("beat").and_then(|x| x.as_f64()).unwrap_or(0.0) as f32;
    let silent = v
        .get("silent")
        .and_then(|x| x.as_bool())
        .unwrap_or_else(|| energy < 0.02);
    Some(FrameData {
        bands,
        energy,
        beat,
        silent,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::source::SourceEvent;
    use std::io::Write;
    use std::sync::mpsc::channel;
    use std::time::Duration;

    #[test]
    fn parse_frame_line_basic() {
        let line = r#"{"bands":[0.1,0.2,0.3],"energy":0.4,"beat":0.1,"silent":false,"source":"pipewire"}"#;
        let f = parse_frame_line(line).unwrap();
        assert_eq!(f.bands, vec![0.1, 0.2, 0.3]);
        assert_eq!(f.energy, 0.4);
        assert_eq!(f.beat, 0.1);
        assert!(!f.silent);
    }

    #[test]
    fn parse_frame_line_missing_silent_defaults() {
        let line = r#"{"bands":[0.0,0.0],"energy":0.0,"beat":0.0}"#;
        let f = parse_frame_line(line).unwrap();
        assert!(f.silent, "energy<0.02 should default to silent");
    }

    #[test]
    fn parse_frames_skips_blank_and_malformed() {
        let content = "  \nnot json\n{\"bands\":[1.0],\"energy\":0.5}\n";
        let frames = parse_frames(content);
        assert_eq!(frames.len(), 1);
        assert_eq!(frames[0].bands, vec![1.0]);
    }

    #[test]
    fn spawn_requires_path() {
        let (tx, _rx) = channel();
        assert!(spawn("", tx.clone()).is_err());
        assert!(spawn("=", tx).is_err());
    }

    #[test]
    fn spawn_replays_frames_then_exits() {
        let dir = std::env::temp_dir();
        let path = dir.join("omaviz_file_test.jsonl");
        {
            let mut fh = std::fs::File::create(&path).unwrap();
            writeln!(
                fh,
                r#"{{"bands":[0.1,0.2],"energy":0.3,"beat":0.0,"silent":false,"source":"pipewire"}}"#
            )
            .unwrap();
            writeln!(
                fh,
                r#"{{"bands":[0.4,0.5],"energy":0.6,"beat":0.2,"silent":false,"source":"pipewire"}}"#
            )
            .unwrap();
        }
        let (tx, rx) = channel();
        spawn(&format!("={}", path.display()), tx).unwrap();
        let f1 = rx.recv_timeout(Duration::from_secs(3)).unwrap();
        let f2 = rx.recv_timeout(Duration::from_secs(3)).unwrap();
        let exit = rx.recv_timeout(Duration::from_secs(3)).unwrap();
        match (f1, f2, exit) {
            (
                SourceEvent::Frame { bands: b1, .. },
                SourceEvent::Frame { bands: b2, .. },
                SourceEvent::Exit,
            ) => {
                assert_eq!(b1, vec![0.1, 0.2]);
                assert_eq!(b2, vec![0.4, 0.5]);
            }
            _ => panic!("expected two frames then Exit"),
        }
        let _ = std::fs::remove_file(&path);
    }
}
