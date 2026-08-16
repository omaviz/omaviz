# omaviz-spectrum-bridge

> **STATUS: SOURCE NOT IN THIS REPO — but the binary IS committed here as a
> safety copy.** The `omaviz-spectrum-bridge` binary was built outside this repo
> and its Rust source was never committed. To avoid losing the only artifact, a
> copy is kept at `bridge/bin/omaviz-spectrum-bridge` (sha256 below). A
> reconstructed-from-contract source is the longer-term goal (see §Reconstruction).

```
sha256: 2c67a773d5f6eeb16615aeba36c4d17c8cf079285d31c7f68fd0ecdc39667aed
size:   523768 bytes
built:  2026-08-15 (from mtime of the deployed /home/kishan/.local/bin copy)
```

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
   - Consumed by `plugin/BarWidget.qml` → `Model.parseSpectrumLine`
     (`spectrumData.bands/energy/beat`).

## How it is launched
- Spawned by `plugin/BarWidget.qml` `spectrumProc` (Quickshell `Process`,
  `running: true`) at absolute path `/home/kishan/.local/bin/omaviz-spectrum-bridge`.
- A bounded `onExited` retry (max 10, 1.5s apart) self-heals after reboots when
  the socket is not ready at login.

## Reconstruction (TODO)
The source is missing, but the contract above is enough to rebuild a minimal
bridge in Rust:
- Connect the daemon socket (path from `$XDG_RUNTIME_DIR/omaviz.sock`,
  default `/run/user/1000/omaviz.sock`).
- Read OMAV frames (wire format lives in `daemon/src/ipc.rs` / `daemon/src/dsp.rs`).
- Print `{"bands":[...],"energy":f,"beat":f}` per line.
Do **not** ship a reconstructed binary as a drop-in without verifying it produces
identical frame output against the committed `bridge/bin/omaviz-spectrum-bridge`.
