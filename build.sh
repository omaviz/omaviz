#!/usr/bin/env bash
# Build the omaviz-engine and place the binary directly into bin/
# (Architecture A: the plugin is a self-contained, zero-build
# drop-in, so the engine binary is a committed artifact living at
# bin/omaviz-engine).
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_DIR="$SRC/engine"
OUT_DIR="$SRC/bin"
OUT_BIN="$OUT_DIR/omaviz-engine"

mkdir -p "$OUT_DIR"

if ! command -v cargo >/dev/null; then
  echo "cargo not found; expecting a prebuilt engine at $OUT_BIN" >&2
  exit 1
fi

echo "== building omaviz-engine (Rust) =="
( cd "$ENGINE_DIR" && cargo build --release )

# Output the freshly built binary into bin/ (atomic: avoids "Text file busy"
# when the engine is currently running and being overwritten in place).
cp "$ENGINE_DIR/target/release/omaviz-engine" "$OUT_BIN.new"
mv -f "$OUT_BIN.new" "$OUT_BIN"
chmod +x "$OUT_BIN"

echo "engine -> $OUT_BIN"

# ---- GPU shader (Qt6 ShaderEffect needs precompiled .qsb) ----
SHADER_SRC="$SRC/gpu.frag"
SHADER_OUT="$SRC/gpu.qsb"
QSB_BIN="$(command -v qsb || true)"
if [ -z "$QSB_BIN" ] && [ -x /usr/lib/qt6/bin/qsb ]; then QSB_BIN=/usr/lib/qt6/bin/qsb; fi

if [ -n "$QSB_BIN" ]; then
  echo "== compiling GPU shader (qsb) =="
  "$QSB_BIN" "$SHADER_SRC" --qt6 -o "$SHADER_OUT.new" \
    && mv -f "$SHADER_OUT.new" "$SHADER_OUT" \
    && echo "shader -> $SHADER_OUT"
elif [ -f "$SHADER_OUT" ]; then
  echo "qsb not found; using committed $SHADER_OUT" >&2
else
  # No qsb and no prebuilt shader: desktop falls back to Canvas at runtime.
  echo "qsb not found and no prebuilt $SHADER_OUT; GPU path will fall back" >&2
fi
