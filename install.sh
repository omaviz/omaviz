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

# True only when a *desktop entry* is one THIS project created. Very old omaviz
# versions installed `omaviz-desktop.desktop` whose Exec ran the `omaviz` CLI;
# later ones point at our plugin's Desktop.qml. Ownership is judged from the
# Exec/TryExec *command*, never from the word "omaviz" appearing anywhere in the
# file: a user-owned entry that merely mentions the plugin (in Name, Comment, or
# a path inside its own command) is not ours to delete. Requires a [Desktop
# Entry] section and that EVERY command in it is one we shipped.
is_our_legacy_launcher() {
  local file="$1" line cmd cmdword seen=0
  grep -q '^\[Desktop Entry\]' "$file" 2>/dev/null || return 1
  while IFS= read -r line; do
    case "$line" in
      Exec=*|TryExec=*) ;;
      *) continue ;;
    esac
    seen=1
    cmd="${line#*=}"
    cmd="${cmd%%[[:space:]]*}"         # first token = the command itself
    cmd="${cmd%\"}"; cmd="${cmd#\"}"   # strip surrounding quotes
    cmdword="${cmd##*/}"               # basename
    if [ "$cmdword" = "omaviz" ]; then
      continue                         # the CLI we used to ship
    fi
    case "$line" in
      *plugins/*omaviz*) continue ;;   # a path inside an omaviz plugin dir
      *) return 1 ;;                   # foreign command -> not ours
    esac
  done <"$file"
  [ "$seen" = 1 ]
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

# --- managed-path helpers (SHARED contract with uninstall.sh) --------------
# Validate EVERY line of the marker BEFORE deleting anything. A corrupted or
# foreign marker must never let a path escape the plugin directory (empty
# lines, '..' traversal, absolute paths) — and must not cause a partial
# delete either: validation is all-or-nothing, then removal runs.
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

validate_marker "$PLUGIN_DIR/$MARKER" || {
  echo "refusing to touch $PLUGIN_DIR: invalid marker" >&2
  exit 1
}
if command -v rsync >/dev/null; then
  # Remove only files WE shipped in a previous run (listed in the marker),
  # never foreign files a user may have dropped into the plugin dir.
  remove_managed_paths "$PLUGIN_DIR/$MARKER"
  rsync -a \
    --exclude '/engine/' --exclude '/docs/' --exclude '/.git/' \
    --exclude '/tools/' --exclude '/.github/' \
    --exclude '/*.sh' --exclude '/*.md' --exclude '/LICENSE' --exclude '/preview.png' \
    --exclude '/package.json' --exclude '/.gitignore' \
    --exclude "/$MARKER" \
    "$SRC/" "$PLUGIN_DIR/"
else
  # Non-rsync path: never rm -rf the whole dir. Remove only the files we
  # manage (marker lists them), then copy fresh ones in.
  remove_managed_paths "$PLUGIN_DIR/$MARKER"
  cp "$SRC"/manifest.json "$PLUGIN_DIR/"
  cp "$SRC"/*.qml "$SRC"/ModelStore.js "$SRC"/Physics.js "$PLUGIN_DIR/"
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
  for f in "$SRC"/*.qml "$SRC"/ModelStore.js "$SRC"/Physics.js "$SRC"/*.frag "$SRC"/*.qsb; do
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
#   - legacy omaviz-desktop.desktop -> remove ONLY if provably ours (its
#     Exec/TryExec is the `omaviz` CLI or an omaviz plugin path); a user file
#     that merely mentions omaviz is left alone
step "installing app launcher"
mkdir -p "$APPS_DIR"
if [ -f "$LAUNCHER" ] && ! grep -q "^# omaviz-managed$" "$LAUNCHER"; then
  backup "$LAUNCHER"
fi
{
  echo "# omaviz-managed"
  sed "s|^Exec=.*|Exec=quickshell -p $PLUGIN_DIR/Desktop.qml|" "$SRC/assets/omaviz.desktop"
} > "$LAUNCHER"
# Legacy entry from older omaviz versions: remove ONLY when the file is
# provably ours — a desktop entry whose command is the `omaviz` CLI we shipped,
# or a path inside an omaviz plugin dir. A user-owned .desktop that merely
# mentions omaviz is left untouched (see is_our_legacy_launcher).
if [ -f "$LEGACY_LAUNCHER" ]; then
  if is_our_legacy_launcher "$LEGACY_LAUNCHER"; then
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
