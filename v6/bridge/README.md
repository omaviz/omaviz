# omaviz-spectrum-bridge

> **STATUS: SOURCE RECOVERED.** The Rust source is in this directory
> (`src/main.rs`, `Cargo.toml`) — reconstructed from the original Hermes session
> that first wrote it (session `architect/20260815_121541_b511e6`, message 13751).
> It was later lost when that session's working tree was cleared, and recovered
> here from the transcript. The built binary is committed at `bridge/bin/` as a
> safety copy.

## What it does
1. Connects to the `omaviz` daemon's Unix socket at `$XDG_RUNTIME_DIR/omaviz.sock`
   (default `/run/user/1000/omaviz.sock`).
   - If the socket is absent, it sleeps and retries to reconnect (so it survives
     daemon restarts / reboots).
2. Reads **OMAV binary frames** (format defined in `daemon/src/ipc.rs`):
   ```
   magic  u32 = 0x4F4D4156 ("OMAV")  little-endian
   n_bands u16
   flags  u16   (bit0 = silent)
   energy f32
   beat   f32
   bands  [f32; n_bands]
   ```
3. Prints one **JSON object per line** on stdout:
   ```json
   {"bands":[…32 values…],"energy":0.41,"beat":0.0,"silent":false}
   ```
   - Consumed by `plugin/BarWidget.qml` → `Model.parseSpectrumLine`
     (`spectrumData.bands/energy/beat`).

## Build
```bash
cd bridge
cargo build --release
# binary: target/release/omaviz-spectrum-bridge
```

## Verification
The reconstructed binary was diff-tested against the previously-deployed binary
over the live socket: **identical frame output** (all 178 overlapping lines
byte-identical). With a 440 Hz test tone it emits non-silent frames with the
expected spectral peak — confirming the full daemon → socket → bridge → bar path
works with the source-backed build.

## Deploy
Installed to `~/.local/bin/omaviz-spectrum-bridge` by the repo's install script
(see root `install.sh`). The bar's `spectrumProc` spawns it at that absolute
path; a bounded `onExited` retry (max 10, 1.5s apart) self-heals after reboots.
