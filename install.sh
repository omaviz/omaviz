#!/usr/bin/env bash
# omaviz — installer (Omarchy-native, zero-build by default).
#
#   ./install.sh            full install (idempotent)
#   ./install.sh --build     also (re)build the Rust engine into plugin/bin
#
# Architecture A: the plugin directory is a SELF-CONTAINED drop-in. The
# engine binary (plugin/bin/omaviz-engine) is committed, so a plain copy of
# the plugin dir + `omarchy plugin enable` is all that's needed — exactly how
# every other Omarchy plugin installs. No systemd, no socket, no ~/.local/bin.
#
# `./build.sh` produces plugin/bin/omaviz-engine from source; --build here
# just delegates to it when you want to rebuild from the Rust source.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
PLUGIN_DIR="$CFG/omarchy/plugins/org.omaviz.visualizer"
PLUGIN_ID="org.omaviz.visualizer"

DO_BUILD=0
for a in "$@"; do
  case "$a" in
    --build) DO_BUILD=1 ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

say()  { printf '  %s\n' "$*"; }
step() { printf '\n== %s ==\n' "$*"; }

# ---------------------------------------------------------------- engine
# Default: the committed binary in plugin/bin is used as-is (zero-build).
# Only build if explicitly requested OR the binary is missing.
if [ "$DO_BUILD" = 1 ]; then
  step "building omaviz-engine (Rust) -> plugin/bin"
  "$SRC/build.sh"
elif [ ! -x "$SRC/plugin/bin/omaviz-engine" ]; then
  step "omaviz-engine missing in plugin/bin — building"
  "$SRC/build.sh"
else
  step "omaviz-engine present (committed) — skipping build"
fi

# ---------------------------------------------------------------- plugin
# Copy the self-contained plugin directory. rsync if available for clean
# updates; otherwise plain cp. The engine binary ships inside plugin/bin.
step "installing Omarchy plugin"
mkdir -p "$PLUGIN_DIR"
if command -v rsync >/dev/null; then
  rsync -a --delete "$SRC/plugin/" "$PLUGIN_DIR/"
else
  rm -rf "$PLUGIN_DIR"
  cp -r "$SRC/plugin" "$CFG/omarchy/plugins/$PLUGIN_ID"
fi
chmod +x "$PLUGIN_DIR/bin/omaviz-engine"
say "plugin -> $PLUGIN_DIR"

# ---------------------------------------------------------------- launcher
# App-launcher entry: opens the desktop window directly (quickshell -p).
# Desktop.qml self-claims config desktop.active on open, so the mini hides
# no matter which path launched it. Replaces any stale `omaviz start` entry
# that pointed at a CLI that no longer exists.
step "installing app launcher"
mkdir -p "$HOME/.local/share/applications"
cp -f "$SRC/plugin/assets/omaviz.desktop" "$HOME/.local/share/applications/omaviz.desktop"
rm -f "$HOME/.local/share/applications/omaviz-desktop.desktop"
say "launcher -> $HOME/.local/share/applications/omaviz.desktop"

# ---------------------------------------------------------------- enable
# The bar-widget is NOT auto-enabled just by copying files — it must be
# explicitly enabled or it stays `disabled` and never mounts (no mini, no
# engine, no detach). Enable LAST (after files are in place) so there is no
# race with the live shell reloading mid-copy, then restart so it mounts.
step "enabling plugin"
if command -v omarchy >/dev/null; then
  omarchy plugin enable "$PLUGIN_ID" 2>/dev/null || true
  omarchy-restart-shell >/dev/null 2>&1 || true
  say "plugin enabled: $PLUGIN_ID"
fi

step "done"
say "engine: plugin-local (no systemd, no socket)"
say "plugin: $PLUGIN_ID enabled in the bar"
say "verify: omarchy-restart-shell, then play audio and open the panel (SOURCE: PipeWire)"
