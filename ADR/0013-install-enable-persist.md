# ADR-0013: install.sh must actually persist `omarchy plugin enable` (T-024)

- **Status:** Accepted (spec for T-024)
- **Date:** 2026-08-20
- **Lane:** architect (this ADR) → dev (impl `install.sh`) → tester (verify `omarchy plugin list` shows `enabled` after a clean install) → reviewer (grade)
- **Referenced by:** `APPLICATION_SPEC.md` §9 (troubleshooting), §13 (roadmap #27)
- **Supersedes:** none · **Superseded by:** none

## 1. Context

The plugin's "zero-build drop-in install" (roadmap #2) is **not** reliably
achieved by `install.sh` today. Root cause (T-024, empirically confirmed by
lotus): after a clean `./install.sh`, `omarchy plugin list` shows
`org.omaviz.visualizer disabled`. The bar never loads → no mini, no engine, no
detach → the app appears completely dead even though the code is correct.

This is the single biggest reason "nothing works" after a fresh install, and it
is exactly the spec-vs-reality contradiction the user has been demanding we fix:
the spec claims install works (roadmap #2 = Shipped 100%; §9 notes "a freshly
copied plugin is `disabled` by default and must be enabled"), but `install.sh`'s
enable step does not reliably produce the enabled state.

### 1.1 Why the current enable step fails silently

`install.sh` enable block (lines 60–75):
```bash
if command -v omarchy >/dev/null; then
  omarchy plugin enable "$PLUGIN_ID" 2>/dev/null || true
  omarchy-restart-shell >/dev/null 2>&1 || true
  say "plugin enabled: $PLUGIN_ID"
fi
```
Two defects:
1. **The failure is swallowed.** `2>/dev/null || true` means any non-zero exit
   from `omarchy plugin enable` is hidden and install.sh still prints
   "plugin enabled". So the script reports success whether or not the plugin is
   actually enabled.
2. **No verification / race.** `omarchy plugin enable` is run immediately after
   `rsync` of the plugin dir; omarchy may not yet have rescanned the new plugin,
   so the enable can no-op. A manual `omarchy plugin enable` + restart performed
   *after* the copy has settled (lotus's recovery step) **does** work — proving
   the command is correct but the script's timing/registration is the gap.

## 2. Decision — make enable verifiable and loud (spec for dev)

1. **Remove the `|| true` swallow.** Let `omarchy plugin enable` fail loudly so
   a broken install is visible, not reported as success.
2. **Verify after enabling.** After the enable call, assert the plugin is
   registered+enabled:
   ```bash
   omarchy plugin enable "$PLUGIN_ID"
   if ! omarchy plugin list 2>/dev/null | grep -q "org.omaviz.visualizer.*enabled"; then
     # retry once after a rescan/restart so omarchy sees the new dir
     omarchy-restart-shell >/dev/null 2>&1 || true
     omarchy plugin enable "$PLUGIN_ID"
     omarchy plugin list 2>/dev/null | grep -q "org.omaviz.visualizer.*enabled" \
       || { echo "ERROR: plugin did not enable — run: omarchy plugin enable org.omaviz.visualizer" >&2; exit 1; }
   fi
   ```
3. **Order:** copy → enable → verify (retry with a rescan if needed) → final
   restart. Do not print "plugin enabled" unless the verify grep passed.
4. **No other behavior change.** The rsync copy, committed binary, and
   `omarchy-restart-shell` stay as-is.

## 3. Consequences

- **Positive:** a clean `./install.sh` now reliably yields an `enabled` plugin;
  the "fresh install shows nothing" failure (T-024) is gone. Failures surface
  instead of being masked.
- **Negative / cost:** install.sh can exit non-zero if omarchy is unavailable or
  the enable genuinely fails — which is correct (the user should know).
- **Test gate (tester, on a clean machine):** run `./uninstall.sh` then
  `./install.sh`; assert `omarchy plugin list` shows `enabled` *without* a
  manual enable. This is a deploy-integration test (companion to ADR-0006's UI
  gate) and must be green before T-024 is closed.

## 4. Rejected alternatives

- **Document "run `omarchy plugin enable` manually after install":** rejected —
  defeats the "zero-build drop-in install" claim and is the exact trap that made
  the app appear dead for the user. The installer must self-verify.
- **Add a systemd/user-service to force-enable on boot:** rejected — violates
  Architecture A (no systemd/socket); enable is an omarchy-registry concern.

## 5. References

- `install.sh` — enable block (60–75).
- `APPLICATION_SPEC.md` §9 (troubleshooting: "a freshly copied plugin is
  `disabled` by default and must be enabled"), §13 (roadmap #2, #27).
- `AGENT_TASKS.md` — T-024 (root cause: install.sh enable non-persistent; manual
  enable + restart resolves).
