#!/usr/bin/env bash
# omaviz v7 — uninstaller (reverses install.sh).
#
#   ./uninstall.sh          remove plugin (engine included) + config
#   ./uninstall.sh --purge  also delete ~/.config/omaviz (visuals/config)
#
# v7 has NO systemd service and NO ~/.local/bin binaries — so there is nothing
# to disable there. Removing the plugin directory removes the bundled engine.
#
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
PLUGIN_DIR="$CFG/omarchy/plugins/org.omaviz.visualizer"

PURGE=0
for a in "$@"; do
  case "$a" in
    --purge) PURGE=1 ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

say()  { printf '  %s\n' "$*"; }
step() { printf '\n== %s ==\n' "$*"; }

# ---------------------------------------------------------------- plugin
step "removing Omarchy plugin (bundled engine included)"
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
say "omaviz v7 fully removed (no systemd unit, no ~/.local/bin artifacts)."
