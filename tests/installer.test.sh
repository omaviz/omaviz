#!/usr/bin/env bash
# Sandboxed installer / uninstaller safety tests.
#
# Runs the REAL install.sh and uninstall.sh against a throwaway $HOME with
# stubbed omarchy commands, and asserts the marketplace safety contract:
#   * never delete or replace files omaviz does not own
#   * uninstall is marker-scoped (symmetric with install's managed update)
#   * a crafted marker cannot traverse outside the plugin directory
#
# No real files outside the sandbox are touched. Exits non-zero on any failure.
#
#   ./tests/installer.test.sh
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

ok()  { PASS=$((PASS + 1)); printf '  \033[32m✔\033[0m %s\n' "$1"; }
no()  { FAIL=$((FAIL + 1)); printf '  \033[31m✖\033[0m %s  [%s]\n' "$1" "${2:-}"; }
check() { if eval "${2:-false}"; then ok "$1"; else no "$1" "${2:-}"; fi; }
step() { printf '\n\033[1m== %s ==\033[0m\n' "$1"; }

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

# --- stub the omarchy commands: install.sh must never need the real shell ---
STUBS="$SANDBOX/stubbin"
mkdir -p "$STUBS"
for c in omarchy omarchy-shell omarchy-restart-shell; do
  printf '#!/usr/bin/env bash\nexit 0\n' >"$STUBS/$c"
  chmod +x "$STUBS/$c"
done
export PATH="$STUBS:$PATH"

PD() { printf '%s' "$HOME/.config/omarchy/plugins/org.omaviz.visualizer"; }
LAUNCHER() { printf '%s' "$HOME/.local/share/applications/omaviz.desktop"; }
LEGACY() { printf '%s' "$HOME/.local/share/applications/omaviz-desktop.desktop"; }

new_home() {
  HOME="$SANDBOX/home-$1"
  rm -rf "$HOME"
  mkdir -p "$HOME"
  export HOME
  unset XDG_CONFIG_HOME
}

run_install()   { "$REPO/install.sh"   "$@" >/dev/null 2>&1; }
run_uninstall() { "$REPO/uninstall.sh" "$@" >/dev/null 2>&1; }

# ============================================================ fresh install
step "fresh install"
new_home 01
run_install
check "install exits 0"                 "[ $? -eq 0 ]"
check "plugin dir created"              "[ -d \"$(PD)\" ]"
check "marker written"                  "[ -f \"$(PD)/.omaviz-managed\" ]"
check "native import resolves on disk" "rg -q 'import \"file:.*/native\" as Native' \"$(PD)/VisualCanvas.qml\""
check "generated QML stays managed" "rg -qx 'VisualCanvas.qml' \"$(PD)/.omaviz-managed\""
check "bundled engine installed + exec" "[ -x \"$(PD)/bin/omaviz-engine\" ]"
check "our launcher installed"          "[ -f \"$(LAUNCHER)\" ]"
# A `.git` FILE (worktree/submodule) is not matched by the '/.git/' directory
# pattern, so it used to be copied into the plugin dir. Nothing dev-only may
# ship inside the plugin.
check "no dev-only files leaked into the plugin dir" \
  "[ ! -e \"$(PD)/.git\" ] && [ ! -e \"$(PD)/.gitignore\" ] && [ ! -e \"$(PD)/package.json\" ] && [ ! -e \"$(PD)/engine\" ] && [ ! -e \"$(PD)/docs\" ] && [ ! -e \"$(PD)/tools\" ]"
check "no repository script is installed" \
  "! ls \"$(PD)\"/*.sh >/dev/null 2>&1"

# ======================================== user files survive a managed update
step "user files survive a managed re-install"
printf 'my notes\n' >"$(PD)/user-notes.txt"
mkdir -p "$(PD)/my-folder" && printf 'x\n' >"$(PD)/my-folder/keep.txt"
run_install
check "user file survives re-install"   "[ -f \"$(PD)/user-notes.txt\" ]"
check "user folder survives re-install" "[ -f \"$(PD)/my-folder/keep.txt\" ]"

# ============ THE FLAGGED BUG: user files must also survive an UNINSTALL
step "user files survive UNINSTALL (marketplace review blocker)"
run_uninstall
check "uninstall exits 0"               "[ $? -eq 0 ]"
check "user file survives uninstall"    "[ -f \"$(PD)/user-notes.txt\" ]"
check "user folder survives uninstall"  "[ -f \"$(PD)/my-folder/keep.txt\" ]"
check "omaviz manifest removed"         "[ ! -e \"$(PD)/manifest.json\" ]"
check "omaviz engine removed"           "[ ! -e \"$(PD)/bin/omaviz-engine\" ]"
check "omaviz marker removed"           "[ ! -e \"$(PD)/.omaviz-managed\" ]"
check "plugin dir kept (still foreign)" "[ -d \"$(PD)\" ]"
check "our launcher removed"            "[ ! -e \"$(LAUNCHER)\" ]"

# ============================== a pristine install uninstalls to nothing
step "pristine managed dir uninstalls completely"
new_home 02
run_install
run_uninstall
check "dir fully removed when nothing foreign" "[ ! -e \"$(PD)\" ]"

# ======================= crafted marker cannot escape the plugin directory
step "marker path-traversal is refused"
new_home 03
run_install
touch "$HOME/ESCAPED"
printf 'assets/../../../../ESCAPED\n' >>"$(PD)/.omaviz-managed"
run_uninstall
check "traversal marker -> non-zero exit" "[ $? -ne 0 ]"
check "file outside plugin dir untouched" "[ -f \"$HOME/ESCAPED\" ]"
check "aborted before deleting our files" "[ -f \"$(PD)/manifest.json\" ]"

printf '..\n' >>"$(PD)/.omaviz-managed" 2>/dev/null || true
new_home 04
run_install
printf '/etc/hosts\n' >>"$(PD)/.omaviz-managed"
run_uninstall
check "absolute marker path -> non-zero exit" "[ $? -ne 0 ]"

# ============================== foreign (unmanaged) dirs are never touched
step "unmanaged dirs are refused, not deleted"
new_home 05
mkdir -p "$(PD)"
printf 'not yours\n' >"$(PD)/foreign.txt"
run_install
check "install refuses unmanaged dir"      "[ $? -ne 0 ]"
check "foreign file intact after install"  "[ -f \"$(PD)/foreign.txt\" ]"
run_uninstall
check "uninstall skips unmanaged dir"      "[ $? -eq 0 ]"
check "foreign file intact after uninstall" "[ -f \"$(PD)/foreign.txt\" ]"
check "dir not deleted"                    "[ -d \"$(PD)\" ]"

# ================================== --force backs up instead of destroying
step "--force backs the dir up rather than destroying it"
new_home 06
mkdir -p "$(PD)"
printf 'precious\n' >"$(PD)/precious.txt"
run_uninstall --force
check "original dir moved away"  "[ ! -e \"$(PD)\" ]"
check "backup created"           "ls -d \"$HOME/.config/omarchy/plugins/org.omaviz.visualizer.bak-\"* >/dev/null 2>&1"
check "backup retains the file"  "grep -rq precious \"$HOME/.config/omarchy/plugins/\""

# ============================ foreign launcher is never removed/overwritten
step "launcher ownership"
new_home 07
mkdir -p "$HOME/.local/share/applications"
printf '[Desktop Entry]\nName=Not ours\n' >"$(LAUNCHER)"
run_uninstall
check "foreign launcher untouched" "[ -f \"$(LAUNCHER)\" ]"
check "foreign launcher not ours"  "grep -qv 'omaviz-managed' \"$(LAUNCHER)\""

new_home 08
mkdir -p "$HOME/.local/share/applications"
printf '[Desktop Entry]\nName=Not ours\n' >"$(LAUNCHER)"
run_install
check "foreign launcher backed up" "ls \"$(LAUNCHER).bak-\"* >/dev/null 2>&1"
check "foreign launcher preserved in backup" "grep -rl 'Not ours' \"$HOME/.local/share/applications/\" >/dev/null 2>&1"

# ======= legacy omaviz-desktop.desktop: only a provably-ours file is removed
# (marketplace review: install.sh must verify ownership, not match "omaviz")
step "legacy launcher ownership"
# (a) the reported case: a USER file that merely mentions omaviz must survive
new_home 11
mkdir -p "$HOME/.local/share/applications"
printf '[Desktop Entry]\nType=Application\nName=Omaviz notes\nComment=my omaviz scratchpad\nExec=gedit /tmp/omaviz-notes.txt\n' >"$(LEGACY)"
run_install
check "install exits 0"                      "[ $? -eq 0 ]"
check "user file mentioning omaviz survives" "[ -f \"$(LEGACY)\" ]"
check "its contents are untouched"           "grep -q 'omaviz-notes.txt' \"$(LEGACY)\""

# (b) a genuinely-ours stale legacy entry (our old CLI) IS removed
new_home 12
mkdir -p "$HOME/.local/share/applications"
printf '[Desktop Entry]\nType=Application\nName=Omaviz\nExec=omaviz start\n' >"$(LEGACY)"
run_install
check "our stale legacy entry removed"       "[ ! -e \"$(LEGACY)\" ]"

# (c) REPORTED CASE: a foreign command that merely lives under a path
#     containing plugins/…omaviz is NOT ours and must survive
new_home 13
mkdir -p "$HOME/.local/share/applications"
printf '[Desktop Entry]\nType=Application\nName=Helper\nExec=/home/user/plugins/tools/omaviz-helper %%f\n' >"$(LEGACY)"
run_install
check "foreign command under plugins/...omaviz survives" "[ -f \"$(LEGACY)\" ]"

# (d) same, but the foreign command names our own plugin directory
new_home 14
mkdir -p "$HOME/.local/share/applications"
printf '[Desktop Entry]\nType=Application\nName=Other\nExec=/opt/plugins/org.omaviz.visualizer/tools/omaviz-helper %%f\n' >"$(LEGACY)"
run_install
check "foreign command naming our plugin dir survives" "[ -f \"$(LEGACY)\" ]"

# (e) a lookalike command is NOT ours (must not prefix-match)
new_home 15
mkdir -p "$HOME/.local/share/applications"
printf '[Desktop Entry]\nType=Application\nName=omaviz-notes\nExec=omaviz-notes-editor %%f\n' >"$(LEGACY)"
run_install
check "lookalike command survives"           "[ -f \"$(LEGACY)\" ]"

# (f) our CLI by absolute path is still ours
new_home 16
mkdir -p "$HOME/.local/share/applications"
printf '[Desktop Entry]\nType=Application\nName=Omaviz\nExec=/usr/local/bin/omaviz start\n' >"$(LEGACY)"
run_install
check "our CLI by absolute path removed"     "[ ! -e \"$(LEGACY)\" ]"

# (g) EVERY command must be ours: our Exec + a foreign TryExec -> not ours
new_home 17
mkdir -p "$HOME/.local/share/applications"
printf '[Desktop Entry]\nType=Application\nName=Omaviz\nExec=omaviz start\nTryExec=omaviz-helper\n' >"$(LEGACY)"
run_install
check "entry with a foreign TryExec survives" "[ -f \"$(LEGACY)\" ]"

# (h) absent file -> the whole path is a clean no-op
new_home 18
run_install
check "no legacy file -> install exits 0"    "[ $? -eq 0 ]"

# ====== user files INSIDE our own directories must survive install+uninstall
# (a v1 marker listed bare directories like assets/; rm -rf on one of those
#  deleted whatever the user had put inside it)
step "user files inside our directories survive"
new_home 19
run_install
check "marker is file-based (no bare dir entry)" "! grep -qx 'assets/' \"$(PD)/.omaviz-managed\""
check "marker records our own asset file"        "grep -qx 'assets/omaviz.desktop' \"$(PD)/.omaviz-managed\""
mkdir -p "$(PD)/assets/notes"
printf 'mine\n' >"$(PD)/assets/my-custom.frag"
printf 'keep\n' >"$(PD)/assets/notes/keep.txt"
printf 'mine\n' >"$(PD)/bin/user-tool"
run_install
check "user file in assets/ survives re-install"    "[ -f \"$(PD)/assets/my-custom.frag\" ]"
check "user subdir in assets/ survives re-install"  "[ -f \"$(PD)/assets/notes/keep.txt\" ]"
run_uninstall
check "uninstall exits 0"                           "[ $? -eq 0 ]"
check "user file in assets/ survives uninstall"     "[ -f \"$(PD)/assets/my-custom.frag\" ]"
check "user subdir in assets/ survives uninstall"   "[ -f \"$(PD)/assets/notes/keep.txt\" ]"
check "user file in bin/ survives uninstall"        "[ -f \"$(PD)/bin/user-tool\" ]"
check "our own asset file IS removed"               "[ ! -e \"$(PD)/assets/omaviz.desktop\" ]"
check "our own engine IS removed"                   "[ ! -e \"$(PD)/bin/omaviz-engine\" ]"
check "plugin dir kept (user files remain)"         "[ -d \"$(PD)\" ]"

# a marker from the older format must not be able to rm -rf a directory
step "a v1 marker (bare directories) cannot delete user files"
new_home 20
run_install
printf 'mine\n' >"$(PD)/assets/user-kept.frag"
printf '# omaviz-managed-marker v1\nmanifest.json\nassets/\nbin/\ntests/\n' >"$(PD)/.omaviz-managed"
run_uninstall
check "uninstall exits 0"                 "[ $? -eq 0 ]"
check "v1 dir entry did not rm -rf"       "[ -f \"$(PD)/assets/user-kept.frag\" ]"
check "v1 marker still removed our file"  "[ ! -e \"$(PD)/manifest.json\" ]"
check "plugin dir kept (user file remains)" "[ -d \"$(PD)\" ]"

# ================================================== symlinks are never followed
step "symlinks are refused, never followed"
new_home 21
mkdir -p "$HOME/elsewhere"
printf 'precious\n' >"$HOME/elsewhere/precious.txt"
mkdir -p "$(dirname "$(PD)")"
ln -s "$HOME/elsewhere" "$(PD)"
run_install
check "install refuses a symlinked plugin dir"   "[ $? -ne 0 ]"
run_uninstall
check "uninstall refuses a symlinked plugin dir" "[ $? -ne 0 ]"
check "symlink target untouched"                 "[ -f \"$HOME/elsewhere/precious.txt\" ]"

new_home 22
mkdir -p "$HOME/.local/share/applications"
printf 'user content\n' >"$HOME/target-file"
ln -s "$HOME/target-file" "$(LAUNCHER)"
run_install
check "install exits 0"                    "[ $? -eq 0 ]"
check "launcher is now a real file"        "[ -f \"$(LAUNCHER)\" ] && [ ! -L \"$(LAUNCHER)\" ]"
check "symlink target NOT overwritten"     "grep -q 'user content' \"$HOME/target-file\""
check "the link itself was backed up"      "ls \"$(LAUNCHER).bak-\"* >/dev/null 2>&1"

# ================================================== backups never clobber
step "backups never clobber each other"
new_home 23
mkdir -p "$(PD)"
printf 'first\n' >"$(PD)/foreign.txt"
run_uninstall --force
mkdir -p "$(PD)"
printf 'second\n' >"$(PD)/foreign.txt"
run_uninstall --force
check "two distinct backups exist" "ls -d \"$HOME/.config/omarchy/plugins/org.omaviz.visualizer.bak-\"* 2>/dev/null | grep -qc ."
check "both originals preserved"   "grep -rq 'first' \"$HOME/.config/omarchy/plugins/\" && grep -rq 'second' \"$HOME/.config/omarchy/plugins/\""

# ======================================================= --purge behaviour
step "--purge removes only omaviz's own config"
new_home 09
run_install
mkdir -p "$HOME/.config/omaviz"
printf 'bars = 32\n' >"$HOME/.config/omaviz/config.toml"
mkdir -p "$HOME/.config/other-tool"
printf 'keep\n' >"$HOME/.config/other-tool/cfg"
run_uninstall --purge
check "--purge removes omaviz config" "[ ! -e \"$HOME/.config/omaviz\" ]"
check "--purge leaves other config"   "[ -f \"$HOME/.config/other-tool/cfg\" ]"

new_home 10
run_install
mkdir -p "$HOME/.config/omaviz"
printf 'bars = 32\n' >"$HOME/.config/omaviz/config.toml"
run_uninstall
check "no --purge keeps config" "[ -f \"$HOME/.config/omaviz/config.toml\" ]"

# ========================= symlinked directories inside the plugin directory
# Reported in review: a symlinked INTERMEDIATE directory must not redirect a
# marker-driven operation outside the plugin dir. `rm -f` does not follow a
# symlink at the leaf but does resolve every component above it, so
# `assets/omaviz.desktop` must not reach through a linked `assets/`.
step "a symlinked directory inside the plugin dir never redirects a delete"

new_home 24
run_install
mkdir -p "$HOME/user-assets"
printf 'user data\n' >"$HOME/user-assets/omaviz.desktop"
mv "$(PD)/assets" "$HOME/assets-real"
ln -s "$HOME/user-assets" "$(PD)/assets"
run_uninstall
check "uninstall exits 0"                      "[ $? -eq 0 ]"
check "the OUTSIDE file was not deleted"       "[ -f \"$HOME/user-assets/omaviz.desktop\" ]"
check "and it still has its contents"          "grep -q 'user data' \"$HOME/user-assets/omaviz.desktop\""
check "the symlink itself survived"            "[ -L \"$(PD)/assets\" ]"
check "our files elsewhere were still removed" "[ ! -e \"$(PD)/bin/omaviz-engine\" ] && [ ! -e \"$(PD)/manifest.json\" ]"
check "the plugin dir was kept (link remains)" "[ -d \"$(PD)\" ]"

new_home 25
run_install
mkdir -p "$HOME/user-assets"
mv "$(PD)/assets" "$HOME/assets-real"
ln -s "$HOME/user-assets" "$(PD)/assets"
run_install
check "managed re-install refuses"             "[ $? -ne 0 ]"
check "nothing was written outside"            "[ -z \"$(ls -A \"$HOME/user-assets\")\" ]"
run_install --force
check "--force still exits 0"                  "[ $? -eq 0 ]"
check "the link was moved aside, not followed" "ls -d \"$(PD).bak-\"* >/dev/null 2>&1"
check "the user dir is still empty"            "[ -z \"$(ls -A \"$HOME/user-assets\")\" ]"
check "a clean plugin dir was installed"       "[ -f \"$(PD)/manifest.json\" ] && [ ! -L \"$(PD)/assets\" ]"

# A symlink at the LEAF is unlinked, never followed: the file it points at lives
# outside the plugin dir and is not ours to delete.
new_home 26
run_install
printf 'outside\n' >"$HOME/target"
ln -s "$HOME/target" "$(PD)/manifest.json"
run_uninstall
check "uninstall exits 0"                      "[ $? -eq 0 ]"
check "the symlink target survived"            "[ -f \"$HOME/target\" ]"
check "its contents are untouched"             "grep -q outside \"$HOME/target\""

# ================================================================ summary
printf '\n\033[1m== installer/uninstaller safety ==\033[0m\n'
printf '  %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
printf '  all safety scenarios hold\n'
