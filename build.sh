#!/usr/bin/env bash
# Build the omaviz-engine and place the binary directly into plugin/bin/
# (Architecture A: the plugin directory is a self-contained, zero-build
# drop-in, so the engine binary is a committed artifact living at
# plugin/bin/omaviz-engine).
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_DIR="$SRC/engine"
OUT_DIR="$SRC/plugin/bin"
OUT_BIN="$OUT_DIR/omaviz-engine"

mkdir -p "$OUT_DIR"

if ! command -v cargo >/dev/null; then
  echo "cargo not found; expecting a prebuilt engine at $OUT_BIN" >&2
  exit 1
fi

echo "== building omaviz-engine (Rust) =="
( cd "$ENGINE_DIR" && cargo build --release )

# Output the freshly built binary into plugin/bin/
cp "$ENGINE_DIR/target/release/omaviz-engine" "$OUT_BIN.new"
mv -f "$OUT_BIN.new" "$OUT_BIN"
chmod +x "$OUT_BIN"

echo "engine -> $OUT_BIN"
