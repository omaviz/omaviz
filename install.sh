#!/usr/bin/env bash
# omaviz v7 — installer.
#
#   ./install.sh            full install (idempotent)
#   ./install.sh --no-build  skip `cargo build`; use existing plugin/bin/omaviz-engine
#
# v7 is a SINGLE PACKAGE: the audio engine (a Rust binary) is built and placed
# INSIDE the plugin directory (plugin/bin/omaviz-engine). There is NO systemd
# service, NO Unix socket, and NO ~/.local/bin binaries. The Quickshell bar
# widget spawns the bundled engine by plugin-relative path.
#
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
PLUGIN_DIR="$CFG/omarchy/plugins/org.omaviz.visualizer"
BIN_DIR="$PLUGIN_DIR/bin"

DO_BUILD=1
for a in "$@"; do
  case "$a" in
    --no-build) DO_BUILD=0 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

say()  { printf '  %s\n' "$*"; }
step() { printf '\n== %s ==\n' "$*"; }

# ---------------------------------------------------------------- engine
step "building omaviz-engine (Rust)"
mkdir -p "$BIN_DIR"
if [ "$DO_BUILD" = 1 ]; then
  if ! command -v cargo >/dev/null; then
    echo "cargo not found; expecting a prebuilt engine at plugin/bin/omaviz-engine" >&2
  else
    ( cd "$SRC/engine" && cargo build --release )
    cp "$SRC/engine/target/release/omaviz-engine" "$BIN_DIR/"
  fi
fi
if [ ! -x "$BIN_DIR/omaviz-engine" ]; then
  echo "error: $BIN_DIR/omaviz-engine missing (build failed or --no-build without a prebuilt)" >&2
  exit 1
fi
chmod +x "$BIN_DIR/omaviz-engine"
say "engine -> $BIN_DIR/omaviz-engine"

# ---------------------------------------------------------------- plugin
step "installing Omarchy plugin"
mkdir -p "$PLUGIN_DIR" "$PLUGIN_DIR/visuals"
cp "$SRC/plugin/manifest.json"        "$PLUGIN_DIR/"
cp "$SRC/plugin/BarWidget.qml"         "$PLUGIN_DIR/"
cp "$SRC/plugin/Panel.qml"             "$PLUGIN_DIR/"
cp "$SRC/plugin/Desktop.qml"           "$PLUGIN_DIR/"
cp "$SRC/plugin/Model.js"              "$PLUGIN_DIR/"
cp "$SRC/plugin/VisualCanvas.qml"      "$PLUGIN_DIR/"
cp "$SRC/plugin/visuals/"*.toml        "$PLUGIN_DIR/visuals/"
# engine bin already in place (built above)
say "plugin -> $PLUGIN_DIR"

# NOTE: do NOT run `omarchy plugin enable` here. The plugin is already declared
# in the user's shell.json (or the omarchy default set), so enabling is
# redundant — and doing it while files are still being copied races with the
# live shell's reload, producing "PluginRegistry.setEnabled: unknown plugin"
# and a spurious shell self-restart. Copying the files is sufficient; the
# restart below picks them up cleanly.

# ---------------------------------------------------------------- reload
step "reloading Omarchy shell"
if command -v omarchy-restart-shell >/dev/null; then
  omarchy-restart-shell || true
  say "shell reloaded"
else
  say "omarchy-restart-shell not found; restart the shell manually"
fi

step "done"
say "engine: plugin-local (no systemd, no socket)"
say "plugin: org.omaviz.visualizer enabled in the bar"
say "verify: omarchy-restart-shell, then play audio and open the panel (SOURCE: PipeWire)"
