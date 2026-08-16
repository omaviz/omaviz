#!/usr/bin/env bash
# omaviz — unified installer for daemon + bridge + Omarchy plugin.
#
#   ./install.sh            full install (idempotent)
#   ./install.sh --no-daemon-binary   skip installing the daemon binary
#                                      (keep an existing ~/.local/bin/omaviz)
#   ./install.sh --build-daemon        build the daemon from daemon/src too
#                                      (requires cargo + the egui/wgpu deps;
#                                       the committed daemon/bin/omaviz is the
#                                       historical v0.2.0 build and may differ
#                                       from your running daemon)
#
# Manages all three pieces together so they never drift:
#   1. daemon   -> ~/.local/bin/omaviz  +  systemd user unit (enabled, autostart)
#   2. bridge   -> ~/.local/bin/omaviz-spectrum-bridge  (built from bridge/src)
#   3. plugin   -> ~/.config/omarchy/plugins/org.omaviz.visualizer/
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${PREFIX:-$HOME/.local}"
BIN="$PREFIX/bin"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
PLUGIN_DIR="$CFG/omarchy/plugins/org.omaviz.visualizer"
UNIT_DIR="$CFG/systemd/user"
UNIT="$UNIT_DIR/omaviz.service"

DO_DAEMON_BIN=1 DO_BUILD_DAEMON=0
for a in "$@"; do
  case "$a" in
    --no-daemon-binary) DO_DAEMON_BIN=0 ;;
    --build-daemon)     DO_BUILD_DAEMON=1 ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

say()  { printf '  %s\n' "$*"; }
step() { printf '\n== %s ==\n' "$*"; }

# ---------------------------------------------------------------- bridge
step "building + installing spectrum bridge"
if ! command -v cargo >/dev/null; then
  echo "cargo not found; copying prebuilt bridge/bin instead" >&2
  cp "$SRC/bridge/bin/omaviz-spectrum-bridge" "$BIN/"
else
  ( cd "$SRC/bridge" && cargo build --release )
  cp "$SRC/bridge/target/release/omaviz-spectrum-bridge" "$BIN/"
fi
chmod +x "$BIN/omaviz-spectrum-bridge"
say "bridge -> $BIN/omaviz-spectrum-bridge"

# ---------------------------------------------------------------- daemon
step "installing daemon"
if [ "$DO_BUILD_DAEMON" = 1 ]; then
  ( cd "$SRC/daemon" && cargo build --release )
  cp "$SRC/daemon/target/release/omaviz" "$BIN/"
  say "daemon built from source -> $BIN/omaviz"
elif [ "$DO_DAEMON_BIN" = 1 ]; then
  if [ -x "$BIN/omaviz" ]; then
    say "keeping existing $BIN/omaviz (use --build-daemon to replace)"
  elif [ -f "$SRC/daemon/bin/omaviz" ]; then
    cp "$SRC/daemon/bin/omaviz" "$BIN/"
    chmod +x "$BIN/omaviz"
    say "daemon -> $BIN/omaviz (from daemon/bin safety copy)"
  else
    say "no daemon binary to install; expecting $BIN/omaviz already present"
  fi
fi

# systemd user unit
mkdir -p "$UNIT_DIR"
# The committed unit hardcodes /usr/bin/omaviz; point ExecStart at our PREFIX bin.
sed "s#^ExecStart=.*#ExecStart=$BIN/omaviz daemon#" "$SRC/daemon/integration/omaviz.service" > "$UNIT"
systemctl --user daemon-reload
systemctl --user enable --now omaviz.service
say "daemon service enabled + started"

# ---------------------------------------------------------------- plugin
step "installing Omarchy plugin"
mkdir -p "$PLUGIN_DIR"
# copy plugin sources (flattened: the repo keeps them under plugin/)
cp "$SRC/plugin/manifest.json"        "$PLUGIN_DIR/"
cp "$SRC/plugin/BarWidget.qml"         "$PLUGIN_DIR/"
cp "$SRC/plugin/Panel.qml"             "$PLUGIN_DIR/"
cp "$SRC/plugin/Desktop.qml"           "$PLUGIN_DIR/"
cp "$SRC/plugin/Model.js"              "$PLUGIN_DIR/"
cp "$SRC/plugin/VisualCanvas.qml"      "$PLUGIN_DIR/"
mkdir -p "$PLUGIN_DIR/visuals"
cp "$SRC/plugin/visuals/"*.toml        "$PLUGIN_DIR/visuals/"
say "plugin -> $PLUGIN_DIR"

# Enable the plugin in the bar so the bar widget (and its bridge) actually loads.
if command -v omarchy >/dev/null; then
  omarchy plugin enable org.omaviz.visualizer 2>/dev/null || true
  say "plugin enabled in bar"
fi

# ---------------------------------------------------------------- reload
step "reloading Omarchy shell"
if command -v omarchy-restart-shell >/dev/null; then
  omarchy-restart-shell || true
  say "shell reloaded"
else
  say "omarchy-restart-shell not found; restart the shell manually"
fi

step "done"
say "daemon:   systemctl --user status omaviz.service"
say "bridge:   spawned automatically by the bar widget"
say "plugin:   org.omaviz.visualizer enabled in the bar"
