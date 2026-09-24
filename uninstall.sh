#!/usr/bin/env bash
# omaviz — uninstaller (reverses install.sh).
#
#   ./uninstall.sh          remove plugin (engine included) + launcher
#   ./uninstall.sh --purge  also delete ~/.config/omaviz (visuals/config)
#   ./uninstall.sh --force  remove even if the plugin dir is not
#                           omaviz-managed (a backup is taken first)
#
# v7 has NO systemd service and NO ~/.local/bin binaries — so there is nothing
# to disable there. Removing the plugin directory removes the bundled engine.
#
# Safety model (marketplace review): never deletes files omaviz does not own.
# The plugin dir is only removed if it carries our management marker (or
# --force, which backs it up first); the launcher is only removed if it is
# ours (marker comment); foreign files are always left in place.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
PLUGIN_DIR="$CFG/omarchy/plugins/org.omaviz.visualizer"
MARKER=".omaviz-managed"
APPS_DIR="$HOME/.local/share/applications"
LAUNCHER="$APPS_DIR/omaviz.desktop"

PURGE=0
FORCE=0
for a in "$@"; do
  case "$a" in
    --purge) PURGE=1 ;;
    --force) FORCE=1 ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

say()  { printf '  %s\n' "$*"; }
step() { printf '\n== %s ==\n' "$*"; }

backup() {
  local path="$1"
  local bk="${path}.bak-$(date +%Y%m%d-%H%M%S)"
  mv "$path" "$bk"
  say "backed up: $path -> $bk"
}

# ---------------------------------------------------------------- plugin
step "removing Omarchy plugin (bundled engine included)"
if [ -e "$PLUGIN_DIR" ]; then
  if [ -f "$PLUGIN_DIR/$MARKER" ]; then
    if command -v omarchy >/dev/null; then
      omarchy plugin remove org.omaviz.visualizer --yes 2>/dev/null || true
    fi
    rm -rf "$PLUGIN_DIR"
    say "removed $PLUGIN_DIR"
  elif [ "$FORCE" = 1 ]; then
    say "$PLUGIN_DIR is not omaviz-managed; --force given"
    backup "$PLUGIN_DIR"
  else
    say "SKIPPED $PLUGIN_DIR — not omaviz-managed ($MARKER missing);"
    say "  nothing was deleted. Re-run with --force if you really want it gone"
    say "  (a timestamped backup is taken first)."
  fi
fi

# ---------------------------------------------------------------- launcher
# Remove the app launcher ONLY if it is ours (marker comment inside).
if [ -f "$LAUNCHER" ]; then
  if grep -q "^# omaviz-managed$" "$LAUNCHER"; then
    rm -f "$LAUNCHER"
    say "removed app launcher"
  else
    say "left launcher alone (not omaviz-managed): $LAUNCHER"
  fi
fi

# ---------------------------------------------------------------- config
if [ "$PURGE" = 1 ]; then
  step "purging config"
  if [ -d "$CFG/omaviz" ]; then
    rm -rf "$CFG/omaviz"
    say "removed $CFG/omaviz"
  fi
fi

# ---------------------------------------------------------------- reload
step "reloading Omarchy shell"
if command -v omarchy-restart-shell >/dev/null; then
  omarchy-restart-shell || true
fi

step "done"
say "omaviz fully removed (no systemd unit, no ~/.local/bin artifacts)."
