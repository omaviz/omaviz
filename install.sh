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
# Uniquifies the name so a second backup in the same second cannot clobber the
# first. `mv` moves a symlink itself, never its target.
backup() {
  local path="$1" bk n=1
  bk="${path}.bak-$(date +%Y%m%d-%H%M%S)"
  while [ -e "$bk" ] || [ -L "$bk" ]; do
    bk="${path}.bak-$(date +%Y%m%d-%H%M%S)-$n"
    n=$((n + 1))
  done
  mv "$path" "$bk"
  say "backed up: $path -> $bk"
}

# Commands this project has actually shipped in a desktop entry. Ownership is
# judged ONLY against these exact command names — never against a path or a
# substring. An entry whose command is some other program that merely lives
# under a path containing "plugins" or "omaviz" (e.g.
# /home/user/plugins/tools/omaviz-helper) is NOT ours and must not be removed.
OUR_LAUNCHER_COMMANDS="omaviz"

# True only when a desktop entry is one THIS project created: it must have a
# [Desktop Entry] section AND every Exec=/TryExec= command in it must be one of
# OUR_LAUNCHER_COMMANDS. Anything else is left untouched.
is_our_legacy_launcher() {
  local file="$1" line cmd word seen=0
  [ -f "$file" ] || return 1
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
    word="${cmd##*/}"                  # basename only — no path heuristic
    case " $OUR_LAUNCHER_COMMANDS " in
      *" $word "*) continue ;;         # a command we shipped
      *) return 1 ;;                   # anything else -> not ours
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
# The marker records ONLY files this installer wrote, as relative paths, one
# per line. '#' lines are comments. Validation runs over EVERY line BEFORE
# anything is deleted: a corrupt or hostile marker must not escape the plugin
# directory (traversal, absolute paths) and must not cause a partial delete.
validate_marker() {
  local mf="$1" entry
  [ -f "$mf" ] || return 0
  while IFS= read -r entry; do
    case "$entry" in
      ''|\#*) continue ;;                                    # blank / comment
      *..*) echo "invalid marker entry (path traversal): $entry" >&2; return 1 ;;
      /*)   echo "invalid marker entry (absolute path): $entry" >&2; return 1 ;;
    esac
  done < "$mf"
  return 0
}
# True only when the relative path stays inside $PLUGIN_DIR: not absolute, no
# traversal, and NO INTERMEDIATE DIRECTORY IS A SYMLINK. `rm -f` does not follow
# a symlink at the leaf, but it DOES resolve every component above it — so
# replacing `assets/` with a link to a user directory would make the marker
# entry `assets/omaviz.desktop` delete a file OUTSIDE the plugin dir, exactly
# the boundary these scripts promise to respect.
managed_path_is_contained() {
  local rel="$1" cur="$PLUGIN_DIR" part
  [ -n "$rel" ] || return 1
  case "$rel" in /*|*..*) return 1 ;; esac
  while [ "$rel" != "${rel%%/*}" ]; do        # while an intermediate remains
    part="${rel%%/*}"; rel="${rel#*/}"
    cur="$cur/$part"
    [ -d "$cur" ] && [ ! -L "$cur" ] || return 1
  done
  [ -n "$rel" ]
}
# Remove ONLY what the marker proves we installed.
#   * a plain path          -> rm -f  (a file we shipped)
#   * a path ending in '/'  -> NEVER recursive. A marker from the older v1
#                              format listed whole directories; deleting those
#                              with `rm -rf` would destroy files the user added
#                              inside them. Such an entry is only rmdir'd, so a
#                              directory still holding anything survives, and
#                              re-installing simply overwrites our own files.
# Either way the entry is skipped unless it is provably contained, so a
# symlinked intermediate can never redirect the operation out of the plugin dir.
remove_managed_paths() {
  local mf="$1" entry rel
  [ -f "$mf" ] || return 0
  while IFS= read -r entry; do
    case "$entry" in
      ''|\#*) continue ;;
    esac
    rel="${entry%/}"
    if ! managed_path_is_contained "$rel"; then
      echo "skipped marker entry (leaves the plugin dir): $entry" >&2
      continue
    fi
    case "$entry" in
      */) rmdir "${PLUGIN_DIR:?}/$rel" 2>/dev/null || true ;;
      *)  rm -f "${PLUGIN_DIR:?}/$rel" ;;
    esac
  done < "$mf"
}
# Drop directories that became empty, deepest-first. `rmdir` never recurses,
# so any directory still holding a user's file is left exactly as it is.
prune_empty_dirs() {
  local d
  [ -d "$PLUGIN_DIR" ] || return 0
  while IFS= read -r d; do
    rmdir "$d" 2>/dev/null || true
  done < <(find "$PLUGIN_DIR" -mindepth 1 -depth -type d 2>/dev/null)
}

# Never operate through a symlinked plugin dir: every path below is resolved
# relative to $PLUGIN_DIR, so a symlink would aim our deletions at its target.
if [ -L "$PLUGIN_DIR" ]; then
  echo "refusing to touch $PLUGIN_DIR: it is a symlink" >&2
  exit 1
fi

# The same boundary, on the WRITE side: rsync, `chmod` and `>` all resolve
# intermediate components, so a plugin dir whose own subdirectory has been
# replaced by a link would receive our files OUTSIDE it. Refuse; --force backs
# the whole directory up (`mv` moves a link, never through it) and installs
# fresh. Plugin folders may not contain symlinks anyway.
if [ -d "$PLUGIN_DIR" ]; then
  link="$(find "$PLUGIN_DIR" -mindepth 1 -type l -print -quit 2>/dev/null || true)"
  if [ -n "$link" ]; then
    if [ "$DO_FORCE" = 1 ]; then
      say "$PLUGIN_DIR contains a symlink ($link); --force given — backing it up"
      backup "$PLUGIN_DIR"
      mkdir -p "$PLUGIN_DIR"
    else
      {
        echo "refusing to install into $PLUGIN_DIR: it contains a symlink:"
        echo "  $link"
        echo "  plugin folders may not contain symlinks, and writing through one"
        echo "  would place files outside the plugin dir."
        echo "  Re-run with --force to back the directory up and install fresh."
      } >&2
      exit 1
    fi
  fi
fi

validate_marker "$PLUGIN_DIR/$MARKER" || {
  echo "refusing to touch $PLUGIN_DIR: invalid marker" >&2
  exit 1
}
# Remove only files WE shipped in a previous run (listed in the marker) — never
# foreign files a user may have dropped into the plugin dir — then prune the
# directories that emptied out. Both steps are non-recursive.
remove_managed_paths "$PLUGIN_DIR/$MARKER"
prune_empty_dirs

if command -v rsync >/dev/null; then
  rsync -a \
    --exclude '/engine/' --exclude '/renderer/' --exclude '/docs/' --exclude '/.git' \
    --exclude '/tools/' --exclude '/.github/' \
    --exclude '/*.sh' --exclude '/*.md' --exclude '/LICENSE' --exclude '/preview.png' \
    --exclude '/package.json' --exclude '/.gitignore' \
    --exclude "/$MARKER" \
    "$SRC/" "$PLUGIN_DIR/"
else
  # Non-rsync path: plain copies of the same file set.
  cp "$SRC"/manifest.json "$PLUGIN_DIR/"
  cp "$SRC"/*.qml "$SRC"/ModelStore.js "$SRC"/Physics.js "$PLUGIN_DIR/"
  # Optional file classes — copy only those that exist (glob would otherwise
  # fail under `set -e` when a class is absent, e.g. no .frag/.qsb in v8+).
  for f in "$SRC"/*.frag "$SRC"/*.qsb; do
    [ -e "$f" ] && cp "$f" "$PLUGIN_DIR/"
  done
  cp -r "$SRC/assets" "$SRC/bin" "$SRC/native" "$SRC/tests" "$PLUGIN_DIR/"
fi
chmod +x "$PLUGIN_DIR/bin/omaviz-engine"
# Quickshell loads plugin QML from qs:@/qs, where a relative native import
# points into its virtual resource tree. Resolve only the installed copy to
# the real module directory so both shell and standalone Desktop can dlopen it.
python3 - "$PLUGIN_DIR/VisualCanvas.qml" "$PLUGIN_DIR/native" <<'PY'
from pathlib import Path
import sys
qml = Path(sys.argv[1])
source = qml.read_text()
needle = 'import "native" as Native'
if needle not in source:
    raise SystemExit('native import missing from VisualCanvas.qml')
qml.write_text(source.replace(needle, f'import "{Path(sys.argv[2]).resolve().as_uri()}" as Native', 1))
art = qml.parent / "ArtworkColors.qml"
art.write_text(art.read_text().replace(needle, f'import "{Path(sys.argv[2]).resolve().as_uri()}" as Native', 1))
PY
# (Re)write the management marker AFTER the copy: records the paths this
# installer owns — proven, not assumed. A path is claimed only when the file we
# just placed at that path is byte-identical to its counterpart in $SRC. Files
# the user added (or ours that they edited) are therefore never claimed, so no
# later run and no uninstall can remove them.
{
  echo "# omaviz-managed-marker v2 — files below are installed by the omaviz installer"
  while IFS= read -r rel; do
    if [ "$rel" = VisualCanvas.qml ] || [ "$rel" = ArtworkColors.qml ]; then printf '%s\n' "$rel"; continue; fi
    [ -f "$SRC/$rel" ] && cmp -s "$PLUGIN_DIR/$rel" "$SRC/$rel" && printf '%s\n' "$rel"
  done < <(find "$PLUGIN_DIR" -type f ! -name "$MARKER" -printf '%P\n' 2>/dev/null | sort)
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
#   - a symlink                   -> back up the LINK (never write through it)
#   - legacy omaviz-desktop.desktop -> remove ONLY if its Exec/TryExec is a
#     command this project actually shipped (see is_our_legacy_launcher)
step "installing app launcher"
mkdir -p "$APPS_DIR"
if [ -L "$LAUNCHER" ]; then
  # Writing with `>` would follow the symlink and overwrite whatever it points
  # at. Move the link itself aside first, then create a real file.
  backup "$LAUNCHER"
elif [ -f "$LAUNCHER" ] && ! grep -q "^# omaviz-managed$" "$LAUNCHER"; then
  backup "$LAUNCHER"
fi
{
  printf '# omaviz-managed\n'
  # Build the Exec line with printf (not sed) so a path containing sed's
  # delimiter or an '&' cannot corrupt the entry.
  while IFS= read -r l; do
    case "$l" in
      Exec=*) printf 'Exec=quickshell -p %s/Desktop.qml\n' "$PLUGIN_DIR" ;;
      *)      printf '%s\n' "$l" ;;
    esac
  done < "$SRC/assets/omaviz.desktop"
} > "$LAUNCHER"
# Legacy entry from older omaviz versions: removed ONLY when the file is
# provably ours — a desktop entry whose every Exec/TryExec command is one we
# shipped. An entry running some other program that merely lives under a path
# containing "plugins" or "omaviz" is NOT ours and is left untouched.
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
