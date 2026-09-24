# Omaviz engine build attestation

This document binds the executable shipped to users, `bin/omaviz-engine`,
to the reviewed source in `engine/`, the dependency lockfile, the toolchain,
and the container the build runs in. It exists so that anyone can verify the
committed binary was produced from the committed source — without trusting
the maintainer's machine.

## What is attested

| Artifact | Value |
|---|---|
| Engine binary | `bin/omaviz-engine` — SHA256 `fbccdaddca176ef2983d298d99f94d814bc9ea0754007aaa568e639f9efcd589` |
| Source | `engine/` (Rust), committed in this repository |
| Lockfile | `engine/Cargo.lock` — pins every crate version + SHA256 checksum |
| Toolchain | Rust 1.98.1 (`rustc 1.98.1 (48a229cea 2026-09-01)`) |
| Build container | `rust@sha256:f47a8de237dcbb0b0ce1099901e60a89728e3d51f24e664b40e947171538ade7` (`rust:1.98.1-slim-trixie`) |
| System libs | Debian trixie `libpipewire-0.3-dev` (1.2.7), `libclang-dev`, `clang`, `pkg-config` |

## How the binary is produced

Every push to `master` (and every PR touching engine/bin/workflow files)
runs [.github/workflows/repro-build.yml](../.github/workflows/repro-build.yml):

1. **Pinned container** — the build runs inside the digest-pinned image above;
   no floating `rust:latest`, no mutable tag.
2. **Locked dependencies** — `cargo build --release --locked` only uses
   `engine/Cargo.lock`; every crate download is checksum-verified by cargo.
   `--locked` fails if the lockfile and manifests disagree.
3. **Double-build determinism** — the engine is built twice from scratch in
   the same container; the two binaries must be byte-identical (SHA256 equal),
   or the job fails.
4. **Unit tests** — `cargo test --release --locked` must pass.
5. **Smoke test** — the deterministic `gen` backend
   (`--source gen=tone:freq=440`) must emit valid spectrum frames.
6. **Binary match gate** — the fresh CI build must be **byte-identical to the
   committed `bin/omaviz-engine`**, or the job fails. This means the committed
   binary can never silently drift from the source: any source change without
   a matching binary commit turns the branch red.
7. **Signed provenance** — GitHub generates a Sigstore keyless attestation
   binding the binary digest to this repository, the workflow, and the exact
   source commit. Verify with:
   ```
   gh attestation verify <path-to-omaviz-engine> --repo omaviz/omaviz
   ```

## Reproduce it yourself (no GitHub account needed)

With Docker on any Linux machine:

```
tools/repro/verify.sh
```

This builds the engine from source inside the same digest-pinned container
and compares SHA256 digests against the committed binary. PASS means the
shipped executable is bit-for-bit reproducible from the reviewed source.

To rebuild the binary after changing engine source:

```
tools/repro/verify.sh --build
git add bin/omaviz-engine && git commit -m "rebuild engine binary"
```

Always commit the binary in the same commit as the source change it belongs
to — CI enforces this via the binary match gate.

## Why a committed binary at all?

The plugin installs as a self-contained drop-in (`install.sh` copies the
plugin directory into `~/.config/omarchy/plugins/`), matching how every other
Omarchy plugin installs — no Rust toolchain required on the user machine.
The reproducibility pipeline above is what makes shipping a prebuilt
executable acceptable: the binary is never trusted blindly; it is continuously
re-derived from the reviewed source and the build fails if it doesn't match.

## Bootstrapping note

The binary currently committed was itself **built and attested by this CI
workflow** (first during [PR #4](https://github.com/omaviz/omaviz/pull/4),
run [35952135827](https://github.com/omaviz/omaviz/actions/runs/35952135827),
subject `sha256:fbccdaddca176ef2983d298d99f94d814bc9ea0754007aaa568e639f9efcd589`).
Every subsequent push re-verifies it byte-for-byte — the binary match gate
fails if the committed binary ever diverges from a fresh pinned-container
rebuild of the source.

## Re-pinning the toolchain

When updating Rust or the container image, in one commit:

1. Update `IMAGE` in `.github/workflows/repro-build.yml` and
   `tools/repro/verify.sh` to the new digest.
2. Rebuild: `tools/repro/verify.sh --build`
3. Commit the new `bin/omaviz-engine` + workflow + lockfile together.

CI's binary match gate goes green only when all three agree.
