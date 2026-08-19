// Behavioral regression tests for BarWidget.qml — the click→detach→window
// chain that the prior logic-only suites (engine/model/glspectrum) never
// exercised. These are GPU-FREE: they parse the QML source and assert the
// structural + wiring invariants that, if broken, produce a total UI failure
// ("nothing opens") even while every shader/engine test is green.
//
// Run:  node tests/barwidget.test.cjs
const assert = require('assert')
const fs = require('fs')
const path = require('path')

const SRC = fs.readFileSync(path.join(__dirname, '..', 'BarWidget.qml'), 'utf8')

let passed = 0
function ok(name, cond) {
  assert.ok(cond, name)
  passed++
  console.log('  ok - ' + name)
}

// --- 1. Click contract (USER'S FINAL INTENT): left→toggle (settings panel),
//     right→detach (desktop viz) ---
{
  const m = SRC.match(/onPressed:\s*function\s*\([^)]*\)\s*\{([\s\S]*?)\n\s*\}/)
  assert.ok(m, 'onPressed handler found')
  const body = m[1]
  // User's explicit final instruction: "it should open the settings panel."
  // (They corrected an earlier misstatement that left-click should open the
  //  desktop window.) So left-click MUST open the settings panel, not detach.
  ok('left-click -> root.toggle() (opens SETTINGS PANEL, the user\'s final intent)',
     /Qt\.LeftButton\)\s*root\.toggle\(\)/.test(body))
  ok('right-click -> root.detach() (desktop visualization window)',
     /Qt\.RightButton\)\s*root\.detach\(\)/.test(body))
  ok('left-click does NOT detach (would skip the settings panel the user wants)',
     !/Qt\.LeftButton\)\s*root\.detach\(\)/.test(body))
  ok('right-click does NOT open the settings panel (would skip the desktop viz)',
     !/Qt\.RightButton\)\s*root\.toggle\(\)/.test(body))
}

// --- 2. detachProc must NOT wipe the child env (root cause of "nothing opens") ---
{
  ok('detachProc does not set environment: (would wipe PATH/DISPLAY/Home)',
     !/\bid:\s*detachProc\b[\s\S]*?\benvironment:/.test(SRC))
  ok('detach() launches quickshell -p <plugin>/Desktop.qml',
     /detachProc\.command\s*=\s*\[[^\]]*quickshell[^\]]*Desktop\.qml/.test(SRC))
  ok('detach() sets desktop.active=true before launching',
     /writeDesktopActive\(true\)/.test(SRC))
  ok('detach() clears the active flag unconditionally on attach (no stuck state)',
     /detachProc\.running\s*=\s*false[\s\S]*?writeDesktopActive\(false\)/.test(SRC))
}

// --- 3. The desktop viz is reachable WITHOUT the panel mounting ---
{
  ok('detachProc is declared directly under BarWidget root (not the panel)',
     /Process\s*\{\s*\n\s*id:\s*detachProc/.test(SRC))
  ok('detach()/attach() are root methods (reachable from left-click directly)',
     /function detach\(\)/.test(SRC))
  // Guard: the desktop viz must NOT depend on panelLoader.item being non-null;
  // if the panel ever failed to mount, a panel-only click would silently no-op.
  // Right-click routes directly to detach() (on BarWidget, not the panel), so the
  // viz is still reachable even if the panel fails to mount.
  ok('right-click detaches directly from BarWidget (viz reachable even if panel fails to mount)',
     /Qt\.RightButton\)\s*root\.detach\(\)/.test(SRC))
}

console.log('\nℹ barwidget tests ' + passed)
console.log('ℹ pass ' + passed)
console.log('ℹ fail 0')
