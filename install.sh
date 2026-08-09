#!/usr/bin/env bash
# omaviz installer — user-local, no sudo, idempotent.
#
#   ./install.sh              full install
#   ./install.sh --no-waybar  skip the waybar module
#   ./install.sh --no-hypr    skip Hyprland rules/keybinds
#   ./install.sh --no-service skip the systemd user unit
#   ./install.sh --no-build   use an existing target/release/omaviz
#
# Every file this touches is either created by omaviz or edited between
# BEGIN/END omaviz markers, so uninstall.sh can reverse it exactly.

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${PREFIX:-$HOME/.local}"
BIN="$PREFIX/bin/omaviz"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
OMA_CFG="$CFG/omaviz"
UNIT_DIR="$CFG/systemd/user"
WAYBAR_CFG="$CFG/waybar/config.jsonc"
WAYBAR_DIR="$CFG/waybar"
WAYBAR_CSS="$CFG/waybar/style.css"
HYPR_DIR="$CFG/hypr"
HYPR_MAIN="$HYPR_DIR/hyprland.conf"
MARK_BEGIN="# >>> omaviz >>>"
MARK_END="# <<< omaviz <<<"

DO_BUILD=1 DO_WAYBAR=1 DO_HYPR=1 DO_SERVICE=1
for a in "$@"; do
  case "$a" in
    --no-build)   DO_BUILD=0 ;;
    --no-waybar)  DO_WAYBAR=0 ;;
    --no-hypr)    DO_HYPR=0 ;;
    --no-service) DO_SERVICE=0 ;;
    -h|--help)    sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

say()  { printf '  %s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*" >&2; }

backup() {
  local f="$1"
  [ -f "$f" ] || return 0
  [ -f "$f.omaviz-orig" ] && return 0
  cp "$f" "$f.omaviz-orig"
  say "backed up $(basename "$f") -> $(basename "$f").omaviz-orig"
}

# ---------------------------------------------------------------- deps
step "checking dependencies"
missing=0
if ! pkg-config --exists libpipewire-0.3 2>/dev/null; then
  warn "libpipewire-0.3 not found (pacman -S pipewire)"; missing=1
fi
if [ "$DO_BUILD" = 1 ] && ! command -v cargo >/dev/null; then
  warn "cargo not found (pacman -S rust)"; missing=1
fi
[ "$missing" = 1 ] && { echo; echo "install the above, then re-run."; exit 1; }
say "libpipewire $(pkg-config --modversion libpipewire-0.3)"
command -v waybar >/dev/null && say "waybar $(waybar --version 2>&1 | head -1 | awk '{print $2}')" || \
  { warn "waybar not found — skipping mini mode"; DO_WAYBAR=0; }
command -v hyprctl >/dev/null || { warn "hyprctl not found — skipping Hyprland setup"; DO_HYPR=0; }

# ---------------------------------------------------------------- build
if [ "$DO_BUILD" = 1 ]; then
  step "building (release)"
  ( cd "$SRC" && cargo build --release )
fi
[ -x "$SRC/target/release/omaviz" ] || { warn "no binary at target/release/omaviz"; exit 1; }

# ---------------------------------------------------------------- binary + assets
step "installing binary and visuals"
install -Dm755 "$SRC/target/release/omaviz" "$BIN"
say "$BIN"
mkdir -p "$OMA_CFG/visuals"
for f in "$SRC"/visuals/*.wgsl "$SRC"/visuals/*.toml; do
  [ -f "$f" ] && install -Dm644 "$f" "$OMA_CFG/visuals/$(basename "$f")"
done
say "$OMA_CFG/visuals ($("$SRC/target/release/omaviz" visuals 2>/dev/null | wc -l) visualizations)"

# Write the default config only if the user has none.
if [ ! -f "$OMA_CFG/config.toml" ]; then
  "$BIN" config >/dev/null 2>&1 || true
  say "wrote default config.toml"
else
  say "kept existing config.toml"
fi

case ":$PATH:" in
  *":$PREFIX/bin:"*) ;;
  *) warn "$PREFIX/bin is not on your PATH — add it to your shell rc" ;;
esac

# ---------------------------------------------------------------- .desktop + icon (app menu)
step "installing application launcher + icon"
# The XDG spec puts application launchers in $XDG_DATA_HOME/applications
# (default ~/.local/share/applications), NOT under the config dir. A launcher
# placed in ~/.config/applications is never shown by fuzzel/rofi/desktop menus.
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
APPS_DIR="$DATA_HOME/applications"
ICON_DIR="$DATA_HOME/icons/hicolor/scalable/apps"
mkdir -p "$APPS_DIR" "$ICON_DIR"
# Force the absolute Exec path and a desktop-window launch (per user feedback:
# the menu/app entry should open the visualizer window, not settings).
install -Dm644 "$SRC/assets/omaviz.desktop" "$APPS_DIR/omaviz.desktop"
sed -i -e "s|^Exec=.*|Exec=$BIN desktop|" "$APPS_DIR/omaviz.desktop"
install -Dm644 "$SRC/assets/omaviz.svg" "$ICON_DIR/omaviz.svg"
# Refresh the desktop database so it shows in the launcher (fuzzel/rofi/etc).
if command -v update-desktop-database >/dev/null; then
  update-desktop-database "$APPS_DIR" 2>/dev/null || true
fi
say "$APPS_DIR/omaviz.desktop (icon: omaviz.svg)"

# ---------------------------------------------------------------- systemd
if [ "$DO_SERVICE" = 1 ]; then
  step "installing systemd user service"
  mkdir -p "$UNIT_DIR"
  sed "s|/usr/bin/omaviz|$BIN|" "$SRC/integration/omaviz.service" > "$UNIT_DIR/omaviz.service"
  systemctl --user daemon-reload
  systemctl --user enable --now omaviz.service
  sleep 1
  if systemctl --user is-active --quiet omaviz.service; then
    say "omaviz.service active"
  else
    warn "service failed to start: systemctl --user status omaviz.service"
  fi
fi

# ---------------------------------------------------------------- waybar
if [ "$DO_WAYBAR" = 1 ]; then
  step "wiring waybar mini mode"
  if [ ! -f "$WAYBAR_CFG" ]; then
    warn "no $WAYBAR_CFG — skipping"
  elif grep -q "custom/omaviz" "$WAYBAR_CFG"; then
    say "already present in waybar config"
  else
    backup "$WAYBAR_CFG"
    # Regenerate the right-click menu and splice its actions into the module.
    mkdir -p "$WAYBAR_DIR"
    MENU_XML="$WAYBAR_DIR/omaviz-menu.xml"
    "$BIN" menu --out "$MENU_XML" >/dev/null
    MENU_ACTIONS="$("$BIN" menu --out "$MENU_XML" 2>&1 | tail -n +2)"
    python3 - "$WAYBAR_CFG" "$MENU_XML" "$MENU_ACTIONS" <<'PY'
import re, sys
p, menu_xml, menu_actions = sys.argv[1], sys.argv[2], sys.argv[3]

menu_entry = f'''  "custom/omaviz": {{
    "exec": "omaviz mini --width 14",
    "return-type": "json",
    "format": "{{}}",
    "tooltip": true,
    "escape": false,
    "on-click": "omaviz toggle",
    "exec-on-event": false,
    "on-scroll-up": "omaviz sensitivity +0.1",
    "on-scroll-down": "omaviz sensitivity -0.1",
    "menu": "on-click-right",
    "menu-file": "{menu_xml}",
{menu_actions}
  }},
'''

s = open(p).read()
for key in ("modules-right", "modules-center", "modules-left"):
    m = re.search(r'("%s"\s*:\s*\[)' % key, s)
    if m:
        s = s[:m.end()] + '\n    "custom/omaviz",' + s[m.end():]
        break
else:
    sys.exit("no modules-* array found")

m = re.search(r'^\s*\{\s*\n', s)
s = s[:m.end()] + menu_entry + s[m.end():]
open(p, "w").write(s)
PY
    say "added custom/omaviz module + generated menu ($MENU_XML)"
  fi

  if [ -f "$WAYBAR_CSS" ] && ! grep -q "custom-omaviz" "$WAYBAR_CSS"; then
    backup "$WAYBAR_CSS"
    # GTK CSS has no '#' comments — use /* */ markers here.
    {
      echo ""
      echo "/* >>> omaviz >>> */"
      cat "$SRC/integration/waybar-style.css"
      echo "/* <<< omaviz <<< */"
    } >> "$WAYBAR_CSS"
    say "appended waybar styling"
  fi

  if pgrep -x waybar >/dev/null; then
    pkill -SIGUSR2 waybar 2>/dev/null && say "reloaded waybar" || true
  else
    warn "waybar is not running — start it to see mini mode"
  fi
fi

# ---------------------------------------------------------------- hyprland
if [ "$DO_HYPR" = 1 ]; then
  step "installing Hyprland rules and keybinds"
  install -Dm644 "$SRC/integration/hyprland.conf" "$HYPR_DIR/omaviz.conf"
  say "$HYPR_DIR/omaviz.conf"
  if [ -f "$HYPR_MAIN" ] && ! grep -q "omaviz.conf" "$HYPR_MAIN"; then
    backup "$HYPR_MAIN"
    {
      echo ""
      echo "$MARK_BEGIN"
      echo "source = ~/.config/hypr/omaviz.conf"
      echo "$MARK_END"
    } >> "$HYPR_MAIN"
    say "sourced from hyprland.conf"
  else
    say "already sourced"
  fi
  hyprctl reload >/dev/null 2>&1 || true
  errs="$(hyprctl configerrors 2>/dev/null || true)"
  if [ -n "$errs" ] && [ "$errs" != "no errors" ]; then
    warn "Hyprland reported config errors:"; echo "$errs" | head -5
  else
    say "Hyprland reloaded, no config errors"
  fi
fi

# ---------------------------------------------------------------- summary
step "done"
cat <<EOF
  omaviz installed.

    omaviz desktop      SUPER + U            small floating window
    omaviz full         SUPER + SHIFT + U    fullscreen
    omaviz settings     SUPER + CTRL + U     settings panel
    omaviz mini                              waybar module (right-click = menu)

  daemon:  systemctl --user status omaviz.service
  config:  $OMA_CFG/config.toml
  remove:  $SRC/uninstall.sh
EOF
