#!/usr/bin/env bash
# omaviz uninstaller — reverses install.sh exactly.
#
#   ./uninstall.sh          remove omaviz, keep ~/.config/omaviz
#   ./uninstall.sh --purge  also delete config and visuals
#
# Restores waybar/Hyprland files from the .omaviz-orig backups when they
# exist; otherwise strips the marker-delimited blocks in place.

set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local}"
BIN="$PREFIX/bin/omaviz"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
OMA_CFG="$CFG/omaviz"
UNIT_DIR="$CFG/systemd/user"
WAYBAR_CFG="$CFG/waybar/config.jsonc"
WAYBAR_CSS="$CFG/waybar/style.css"
HYPR_DIR="$CFG/hypr"
HYPR_MAIN="$HYPR_DIR/hyprland.conf"

PURGE=0
for a in "$@"; do
  case "$a" in
    --purge) PURGE=1 ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

say()  { printf '  %s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }

restore_or_strip() {
  # Prefer the pristine backup; fall back to removing the marker block.
  local f="$1"
  [ -f "$f" ] || return 0
  if [ -f "$f.omaviz-orig" ]; then
    mv "$f.omaviz-orig" "$f"
    say "restored $(basename "$f") from backup"
  else
    python3 - "$f" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p).read()
s = re.sub(r'\n*# >>> omaviz >>>.*?# <<< omaviz <<<\n?', '\n', s, flags=re.S)
s = re.sub(r'\n*/\* >>> omaviz >>> \*/.*?/\* <<< omaviz <<< \*/\n?', '\n', s, flags=re.S)
# Fallbacks for edits made without markers (e.g. a hand-added source line).
s = re.sub(r'\n[^\n]*#[^\n]*omaviz[^\n]*(?=\nsource *= *[^\n]*omaviz\.conf)', '', s)
s = re.sub(r'\nsource *= *[^\n]*omaviz\.conf[^\n]*', '', s)
# Also drop a waybar module entry / definition if it survived.
s = re.sub(r'\n\s*"custom/omaviz",', '', s)
s = re.sub(r'\n?\s*"custom/omaviz"\s*:\s*\{.*?\n\s*\},\n', '\n', s, flags=re.S)
open(p, 'w').write(s)
PY
    say "stripped omaviz block from $(basename "$f")"
  fi
}

step "stopping processes"
if systemctl --user list-unit-files 2>/dev/null | grep -q '^omaviz.service'; then
  systemctl --user disable --now omaviz.service >/dev/null 2>&1 || true
  say "stopped and disabled omaviz.service"
fi
pkill -f "omaviz daemon"   2>/dev/null && say "killed stray daemon"   || true
pkill -f "omaviz desktop"  2>/dev/null || true
pkill -f "omaviz full"     2>/dev/null || true
pkill -f "omaviz settings" 2>/dev/null || true
pkill -f "omaviz mini"     2>/dev/null || true

step "removing runtime files (locks, socket, mode)"
RT="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
# Whole runtime dir (socket, mode file, etc.).
rm -rf "$RT/omaviz" 2>/dev/null || true
# Stray lock files that may sit at the runtime root.
rm -f "$RT"/omaviz-*.lock 2>/dev/null || true
rm -f "$RT/omaviz.sock" 2>/dev/null || true
rm -f "$RT/omaviz.mode" 2>/dev/null || true
say "removed runtime state under $RT"

step "removing systemd unit"
rm -f "$UNIT_DIR/omaviz.service"
systemctl --user daemon-reload 2>/dev/null || true
say "removed"

step "reverting waybar"
restore_or_strip "$WAYBAR_CFG"
restore_or_strip "$WAYBAR_CSS"
pkill -SIGUSR2 waybar 2>/dev/null && say "reloaded waybar" || true

step "reverting Hyprland"
restore_or_strip "$HYPR_MAIN"
rm -f "$HYPR_DIR/omaviz.conf"
say "removed omaviz.conf"
command -v hyprctl >/dev/null && hyprctl reload >/dev/null 2>&1 || true

step "removing application launcher + icon"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
APPS_DIR="$DATA_HOME/applications"
ICON_DIR="$DATA_HOME/icons/hicolor/scalable/apps"
rm -f "$APPS_DIR/omaviz.desktop" "$ICON_DIR/omaviz.svg"
command -v update-desktop-database >/dev/null && update-desktop-database "$APPS_DIR" 2>/dev/null || true
say "removed omaviz.desktop + icon"

step "removing binary"
rm -f "$BIN"
say "removed $BIN"
rm -f "${XDG_RUNTIME_DIR:-/tmp}/omaviz.sock"

if [ "$PURGE" = 1 ]; then
  step "purging config"
  rm -rf "$OMA_CFG"
  say "removed $OMA_CFG"
else
  printf '\n  kept %s (use --purge to delete)\n' "$OMA_CFG"
fi

step "done"
say "omaviz removed."
