# omaviz-spectrum-bridge

> **STATUS: SOURCE NOT IN THIS REPO.**
> The `omaviz-spectrum-bridge` binary (`/home/kishan/.local/bin/omaviz-spectrum-bridge`)
> is deployed and working, but its **Rust source was never committed** to this
> repository. `git log --all` contains no `spectrum-bridge` source file — it was
> built outside the repo. This directory exists to make that gap explicit and to
> record the binary's observed contract so it can be reconstructed or located.

## What the binary does (observed)
1. Connects to the `omaviz` daemon's Unix socket at `/run/user/1000/omaviz.sock`.
   - If the socket is absent, the binary exits immediately with
     `Error: No such file or directory (os error 2)` (ENOENT). This is why the
     mini bar goes dead when the `omaviz` daemon is down.
2. Reads OMAV spectrum frames from the socket.
3. Prints one **JSON object per line** on stdout:
   ```json
   {"bands":[0.63,0.70,...],"energy":0.30,"beat":0.0}
   ```
   - `bands`: array of 32 float magnitudes (0.0–1.0+).
   - `energy`: scalar float.
   - `beat`: scalar float.
   - Consumed by `BarWidget.qml` → `Model.parseSpectrumLine`
     (`spectrumData.bands/energy/beat`).

## How it is launched
- Spawned by `plugin/BarWidget.qml` `spectrumProc` (Quickshell `Process`,
  `running: true`) at absolute path `/home/kishan/.local/bin/omaviz-spectrum-bridge`.
- A bounded `onExited` retry (max 10, 1.5s apart) self-heals after reboots when
  the socket is not ready at login.

## Recovery options (TODO — needs a decision)
- [ ] Locate the original bridge source (another repo / backup) and add it here.
- [ ] Reconstruct a minimal bridge from this contract (Rust, connects the socket,
      prints the JSON line). Requires knowing the OMAV frame wire format from the
      `omaviz` daemon (`daemon/src/ipc.rs` / `daemon/src/dsp.rs`).
- [ ] Treat the deployed binary as the canonical artifact and document its build
      steps if they surface.

Do **not** fabricate a replacement here without the wire-format spec — an
incorrect bridge would silently break the mini visualizer.
