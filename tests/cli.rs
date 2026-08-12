//! CLI integration tests: drive the built binary as a subprocess (no display
//! server needed — these subcommands are pure stdout).
//! Run: cargo test --test cli

use std::io::BufRead;
use std::process::Command;
use std::time::Duration;

fn bin() -> &'static str {
    env!("CARGO_BIN_EXE_omaviz")
}

#[test]
fn visuals_lists_installed_shaders() {
    let out = Command::new(bin())
        .arg("visuals")
        .output()
        .expect("run omaviz visuals");
    assert!(out.status.success());
    let s = String::from_utf8_lossy(&out.stdout);
    // bars and wave are the required defaults.
    assert!(s.contains("bars"), "visuals must list bars");
    assert!(s.contains("wave"), "visuals must list wave");
}

#[test]
fn mini_emits_valid_waybar_json() {
    // `mini` loops forever; run it briefly and grab one line.
    let mut child = Command::new(bin())
        .args(["mini", "--width", "10"])
        .stdout(std::process::Stdio::piped())
        .spawn()
        .expect("spawn omaviz mini");
    // Collect up to ~1s of output.
    let start = std::time::Instant::now();
    let mut buf = String::new();
    let mut reader = std::io::BufReader::new(child.stdout.take().unwrap());
    let mut line = String::new();
    while start.elapsed() < Duration::from_secs(1) {
        line.clear();
        if reader.read_line(&mut line).unwrap_or(0) == 0 {
            break;
        }
        buf.push_str(&line);
        if line.trim_start().starts_with('{') {
            break;
        }
    }
    let _ = child.kill();
    let _ = child.wait();

    let line = buf.lines().find(|l| l.trim_start().starts_with('{')).expect("mini emitted JSON");
    // Must parse as JSON with the waybar keys.
    let v: serde_json::Value = serde_json::from_str(line.trim())
        .unwrap_or_else(|e| panic!("mini JSON invalid: {e}: {line}"));
    assert!(v.get("text").is_some(), "mini JSON needs 'text'");
    assert!(v.get("class").is_some(), "mini JSON needs 'class'");
    assert!(v.get("tooltip").is_some(), "mini JSON needs 'tooltip'");
}

#[test]
fn mode_roundtrips_through_subcommands() {
    // off -> mini -> off, checking the mode file via `omaviz mode`.
    let _ = Command::new(bin()).arg("off").output();
    let out = Command::new(bin()).arg("mode").output().expect("mode");
    assert_eq!(String::from_utf8_lossy(&out.stdout).trim(), "off");

    // `mini` runs the client loop forever; use the one-shot `mode mini` to set
    // the mode without blocking.
    let _ = Command::new(bin()).args(["mode", "mini"]).output();
    let out = Command::new(bin()).arg("mode").output().expect("mode");
    assert_eq!(String::from_utf8_lossy(&out.stdout).trim(), "mini");

    let _ = Command::new(bin()).arg("off").output();
}
