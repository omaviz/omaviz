#!/usr/bin/env bash
# omaviz — unified uninstaller (reverses install.sh).
#
#   ./uninstall.sh          remove daemon + bridge + plugin, keep config
#   ./uninstall.sh --purge  also delete ~/.config/omaviz (config + visuals)
#
# Stops the daemon, removes the binaries, the systemd unit, and the plugin
# directory. Does not touch anything outside omaviz's own files.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${PREFIX:-$HOME/.local}"
BIN="$PREFIX/bin"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
PLUGIN_DIR="$CFG/omarchy/plugins/org.omaviz.visualizer"
UNIT_DIR="$CFG/systemd/user"
UNIT="$UNIT_DIR/omaviz.service"

PURGE=0
for a in "$@"; do
  case "$a" in
    --purge) PURGE=1 ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

say()  { printf '  %s\n' "$*"; }
step() { printf '\n== %s ==\n' "$*"; }

# ---------------------------------------------------------------- daemon
step "stopping + disabling daemon"
if systemctl --user list-unit-files omaviz.service >/dev/null 2>&1; then
  systemctl --user disable --now omaviz.service 2>/dev/null || true
  say "daemon disabled + stopped"
fi
rm -f "$UNIT"
systemctl --user daemon-reload 2>/dev/null || true
rm -f "$BIN/omaviz"
say "removed $UNIT and $BIN/omaviz"

# ---------------------------------------------------------------- bridge
step "removing spectrum bridge"
rm -f "$BIN/omaviz-spectrum-bridge"
say "removed $BIN/omaviz-spectrum-bridge"

# ---------------------------------------------------------------- plugin
step "removing Omarchy plugin"
if command -v omarchy >/dev/null; then
  omarchy plugin remove org.omaviz.visualizer --yes 2>/dev/null || true
fi
rm -rf "$PLUGIN_DIR"
say "removed $PLUGIN_DIR"

# ---------------------------------------------------------------- config
if [ "$PURGE" = 1 ]; then
  step "purging config"
  rm -rf "$CFG/omaviz"
  say "removed $CFG/omaviz"
fi

# ---------------------------------------------------------------- reload
step "reloading Omarchy shell"
if command -v omarchy-restart-shell >/dev/null; then
  omarchy-restart-shell || true
fi

step "done"
say "omaviz fully removed$( [ "$PURGE" = 1 ] && echo ' (config purged)' )."
