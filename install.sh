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
    # Atomic copy: cp to a temp name then mv into place. A plain `cp` over the
    # running binary fails with "Text file busy"; `mv` just replaces the inode,
    # so an in-use engine keeps running on the old inode until the shell restarts.
    cp "$SRC/engine/target/release/omaviz-engine" "$BIN_DIR/omaviz-engine.new"
    mv -f "$BIN_DIR/omaviz-engine.new" "$BIN_DIR/omaviz-engine"
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

# ---------------------------------------------------------------- enable
# The bar-widget is NOT auto-enabled just by copying files — it must be
# explicitly enabled or it stays `disabled` and never mounts (no mini, no
# engine, no detach). Do this LAST, after the restart, so there is no race
# with the live shell reloading mid-copy.
step "enabling plugin"
if command -v omarchy >/dev/null; then
  omarchy plugin enable org.omaviz.visualizer 2>/dev/null || true
  # one more restart so the freshly-enabled widget actually mounts
  omarchy-restart-shell >/dev/null 2>&1 || true
  say "plugin enabled: org.omaviz.visualizer"
fi

step "done"
say "engine: plugin-local (no systemd, no socket)"
say "plugin: org.omaviz.visualizer enabled in the bar"
say "verify: omarchy-restart-shell, then play audio and open the panel (SOURCE: PipeWire)"
