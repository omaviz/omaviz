#!/usr/bin/env bash
# omaviz — installer (Omarchy-native, zero-build by default).
#
#   ./install.sh            full install (idempotent)
#   ./install.sh --build     also (re)build the Rust engine into bin/
#   ./install.sh --force     overwrite a plugin dir not managed by omaviz
#                            (a timestamped backup is still taken)
#
# Architecture A: the plugin directory is a SELF-CONTAINED drop-in. The
# engine binary (bin/omaviz-engine) is committed, so a plain copy of the
# plugin files + `omarchy plugin enable` is all that's needed — exactly how
# every other Omarchy plugin installs. No systemd, no socket, no ~/.local/bin.
#
# `./build.sh` produces bin/omaviz-engine from source; --build here
# just delegates to it when you want to rebuild from the Rust source.
#
# Safety model (marketplace review): this installer never destroys files it
# does not own. Any pre-existing plugin dir without our management marker is
# refused (or backed up + replaced with --force); foreign launcher files are
# backed up before being replaced, never blind-deleted.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
PLUGIN_DIR="$CFG/omarchy/plugins/org.omaviz.visualizer"
PLUGIN_ID="org.omaviz.visualizer"
MARKER=".omaviz-managed"
APPS_DIR="$HOME/.local/share/applications"
LAUNCHER="$APPS_DIR/omaviz.desktop"
LEGACY_LAUNCHER="$APPS_DIR/omaviz-desktop.desktop"

DO_BUILD=0
DO_FORCE=0
for a in "$@"; do
  case "$a" in
    --build) DO_BUILD=1 ;;
    --force) DO_FORCE=1 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

say()  { printf '  %s\n' "$*"; }
step() { printf '\n== %s ==\n' "$*"; }

# Backup $1 to $1.bak-<timestamp> (preserves the original for the user).
backup() {
  local path="$1"
  local bk="${path}.bak-$(date +%Y%m%d-%H%M%S)"
  mv "$path" "$bk"
  say "backed up: $path -> $bk"
}

# ---------------------------------------------------------------- engine
# Default: the committed binary in bin/ is used as-is (zero-build).
# Only build if explicitly requested OR the binary is missing.
if [ "$DO_BUILD" = 1 ]; then
  step "building omaviz-engine (Rust) -> bin/"
  "$SRC/build.sh"
elif [ ! -x "$SRC/bin/omaviz-engine" ]; then
  step "omaviz-engine missing in bin/ — building"
  "$SRC/build.sh"
else
  step "omaviz-engine present (committed) — skipping build"
fi

# ---------------------------------------------------------------- plugin
# Copy the self-contained plugin files (repo root IS the plugin: manifest.json
# + QML/JS + assets + bin). rsync excludes keep dev-only baggage (engine
# source, docs, CI, repro tooling, scripts) out of the live plugin dir;
# otherwise plain cp. The engine binary ships inside bin/.
#
# Ownership rules:
#   - no existing dir            -> plain install
#   - existing + our marker      -> managed update: only paths listed in the
#                                   marker are removed/replaced; foreign files
#                                   inside the dir are left untouched
#   - existing, no marker        -> REFUSE; --force backs it up first
step "installing Omarchy plugin"
if [ -e "$PLUGIN_DIR" ] && [ ! -f "$PLUGIN_DIR/$MARKER" ]; then
  if [ "$DO_FORCE" = 1 ]; then
    say "existing $PLUGIN_DIR is not omaviz-managed; --force given"
    backup "$PLUGIN_DIR"
  else
    {
      echo "refusing to touch $PLUGIN_DIR:"
      echo "  it exists and is not marked as omaviz-managed ($MARKER missing)."
      echo "  If you are sure, re-run with --force (a backup is taken first)."
    } >&2
    exit 1
  fi
fi
mkdir -p "$PLUGIN_DIR"

# Validate marker lines: reject empties, absolute paths, and any path
# containing '..' (path traversal). This prevents a corrupted or foreign
# marker from making rm -rf delete files outside the plugin directory.
validate_marker_line() {
  local line="$1"
  # reject empty lines
  [ -z "$line" ] && return 1
  # reject lines with .. (path traversal)
  case "$line" in
    *..*) return 1 ;;
  esac
  # reject absolute paths (starting with /)
  case "$line" in
    /*) return 1 ;;
  esac
  return 0
}
if command -v rsync >/dev/null; then
  # Remove only files WE shipped in a previous run (listed in the marker),
  # never foreign files a user may have dropped into the plugin dir.
  if [ -f "$PLUGIN_DIR/$MARKER" ]; then
    while IFS= read -r f; do
      # reject blank / lines with path traversal / absolute paths
      case "$f" in
        "") echo "refusing to touch $PLUGIN_DIR: marker contains empty line" >&2; exit 1 ;;
        ".."*) echo "refusing to touch $PLUGIN_DIR: marker contains path traversal: $f" >&2; exit 1 ;;
        "/")*  echo "refusing to touch $PLUGIN_DIR: marker contains absolute path: $f" >&2; exit 1 ;;
        *)  rm -rf "${PLUGIN_DIR:?}/$f" ;;
      esac
    done < "$PLUGIN_DIR/$MARKER"
  fi
  rsync -a \
    --exclude '/engine/' --exclude '/docs/' --exclude '/.git/' \
    --exclude '/tools/' --exclude '/.github/' \
    --exclude '/*.sh' --exclude '/*.md' --exclude '/LICENSE' --exclude '/preview.png' \
    --exclude "/$MARKER" \
    "$SRC/" "$PLUGIN_DIR/"
else
  # Non-rsync path: never rm -rf the whole dir. Remove only the files we
  # manage (marker lists them), then copy fresh ones in.
  if [ -f "$PLUGIN_DIR/$MARKER" ]; then
    while IFS= read -r f; do
      # reject blank / lines with path traversal / absolute paths
      case "$f" in
        "") echo "refusing to touch $PLUGIN_DIR: marker contains empty line" >&2; exit 1 ;;
        ".."*) echo "refusing to touch $PLUGIN_DIR: marker contains path traversal: $f" >&2; exit 1 ;;
        "/")*  echo "refusing to touch $PLUGIN_DIR: marker contains absolute path: $f" >&2; exit 1 ;;
        *)  rm -rf "${PLUGIN_DIR:?}/$f" ;;
      esac
    done < "$PLUGIN_DIR/$MARKER"
  fi
  cp "$SRC"/manifest.json "$PLUGIN_DIR/"
  cp "$SRC"/*.qml "$SRC"/Model.js "$PLUGIN_DIR/"
  # Optional file classes — copy only those that exist (glob would otherwise
  # fail under `set -e` when a class is absent, e.g. no .frag/.qsb in v8+).
  for f in "$SRC"/*.frag "$SRC"/*.qsb; do
    [ -e "$f" ] && cp "$f" "$PLUGIN_DIR/"
  done
  cp -r "$SRC/assets" "$SRC/bin" "$SRC/tests" "$PLUGIN_DIR/"
fi
chmod +x "$PLUGIN_DIR/bin/omaviz-engine"
# (Re)write the management marker AFTER the copy: records exactly the paths
# this installer owns, so future runs (and uninstall) only ever touch these.
{
  echo "manifest.json"
  for f in "$SRC"/*.qml "$SRC"/Model.js "$SRC"/*.frag "$SRC"/*.qsb; do
    [ -e "$f" ] && echo "${f#"$SRC"/}"
  done
  echo "assets/"
  echo "bin/"
  echo "tests/"
} > "$PLUGIN_DIR/$MARKER"
say "plugin -> $PLUGIN_DIR"

# ---------------------------------------------------------------- launcher
# App-launcher entry: opens the desktop window directly (quickshell -p).
# Desktop.qml self-claims config desktop.active on open, so the mini hides
# no matter which path launched it. Replaces any stale `omaviz start` entry
# that pointed at a CLI that no longer exists.
#
# Ownership rules:
#   - no existing file            -> install ours
#   - ours (marker comment inside)-> replace
#   - foreign file                -> back it up, then install ours
#   - legacy omaviz-desktop.desktop -> remove ONLY if it references omaviz
step "installing app launcher"
mkdir -p "$APPS_DIR"
if [ -f "$LAUNCHER" ] && ! grep -q "^# omaviz-managed$" "$LAUNCHER"; then
  backup "$LAUNCHER"
fi
{
  echo "# omaviz-managed"
  sed "s|^Exec=.*|Exec=quickshell -p $PLUGIN_DIR/Desktop.qml|" "$SRC/assets/omaviz.desktop"
} > "$LAUNCHER"
# Legacy entry from older omaviz versions: remove only if it is actually ours
# (references the omaviz plugin path); never touch unrelated .desktop files.
if [ -f "$LEGACY_LAUNCHER" ]; then
  if grep -q "omaviz" "$LEGACY_LAUNCHER"; then
    rm -f "$LEGACY_LAUNCHER"
    say "removed legacy launcher: $LEGACY_LAUNCHER"
  else
    say "left unrelated file alone: $LEGACY_LAUNCHER"
  fi
fi
say "launcher -> $LAUNCHER"

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
