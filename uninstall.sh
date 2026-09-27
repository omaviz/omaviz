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
# Uninstall is MARKER-SCOPED, symmetric with install.sh's managed update: it
# removes only the paths omaviz shipped (recorded in the marker), so files that
# survive a managed update also survive an uninstall. The plugin directory
# itself is removed only if it is empty afterwards. The launcher is removed
# only if it is ours (marker comment); foreign files are always left in place.
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
# Marker-scoped removal — symmetric with install.sh's managed update.
# Delete ONLY the paths we shipped (recorded in the marker); never foreign
# files the user placed in the plugin dir.
#
# We deliberately do NOT call `omarchy plugin remove` here: for a git-managed
# install (the marketplace clones the repo, so `.git` is always present) that
# command falls back to `rm -rf "$PLUGIN_DIR"`, which would delete unmanaged
# user files — the very thing this safety model forbids.
# `omarchy plugin disable` unloads the plugin from the shell without touching
# any files, which is all we need before removing our own.
validate_marker() {
  local mf="$1" line
  [ -f "$mf" ] || return 0
  while IFS= read -r line; do
    if [ -z "$line" ]; then
      echo "invalid marker entry (empty line) in $mf" >&2
      return 1
    fi
    case "$line" in
      *..*) echo "invalid marker entry (path traversal): $line" >&2; return 1 ;;
      /*)   echo "invalid marker entry (absolute path): $line" >&2; return 1 ;;
    esac
  done < "$mf"
  return 0
}
remove_managed_paths() {
  local mf="$1" f
  [ -f "$mf" ] || return 0
  while IFS= read -r f; do
    rm -rf "${PLUGIN_DIR:?}/$f"
  done < "$mf"
}

step "removing Omarchy plugin (bundled engine included)"
if [ -e "$PLUGIN_DIR" ]; then
  if [ -f "$PLUGIN_DIR/$MARKER" ]; then
    # Validate ALL marker lines first: refuse without deleting anything if the
    # marker is corrupt or hostile (all-or-nothing, no partial delete).
    validate_marker "$PLUGIN_DIR/$MARKER" || {
      echo "refusing to touch $PLUGIN_DIR: invalid marker" >&2
      exit 1
    }
    if command -v omarchy >/dev/null; then
      omarchy plugin disable org.omaviz.visualizer 2>/dev/null || true
    fi
    remove_managed_paths "$PLUGIN_DIR/$MARKER"
    rm -f "$PLUGIN_DIR/$MARKER"
    if rmdir "$PLUGIN_DIR" 2>/dev/null; then
      say "removed $PLUGIN_DIR"
    else
      say "removed omaviz's own files from $PLUGIN_DIR"
      say "kept the directory — it still contains files omaviz does not own:"
      find "$PLUGIN_DIR" -mindepth 1 -maxdepth 1 -printf '      %f\n' 2>/dev/null | sort || true
      say "delete it yourself if you want it gone:"
      say "  omarchy plugin remove org.omaviz.visualizer --yes"
    fi
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
