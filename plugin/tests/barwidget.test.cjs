// Behavioral regression tests for BarWidget.qml — the click contract that the
// prior logic-only suites (engine/model/glspectrum) never exercised. These are
// GPU-FREE: they parse the QML source and assert the structural + wiring
// invariants that, if broken, produce a total UI failure ("nothing opens") even
// while every shader/engine test is green.
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

// --- 1. Click contract (USER'S EXPLICIT, REPEATED INSTRUCTION):
//     1. left-click  -> open settings PANEL (root.toggle())
//     2. NO right-click behavior of any kind.
//   The right-click->detach desktop window was an off-contract invention that
//   also violated "never start a second Quickshell process for a plugin"
//   (omarchy spec) AND the user's stated preference. It is removed.
{
  const m = SRC.match(/onPressed:\s*function\s*\([^)]*\)\s*\{([\s\S]*?)\n\s*\}/)
  assert.ok(m, 'onPressed handler found')
  const body = m[1]
  ok('left-click -> root.toggle() (opens SETTINGS PANEL, the user\'s final intent)',
     /Qt\.LeftButton/.test(body) && /root\.toggle\(\)/.test(body))
  ok('left-click does NOT detach',
     !(/\bdetach\(\)/.test(body)))
  // USER RULE: no right-click behavior at all.
  ok('NO right-click detach() (user: "no right click"; off-contract 2nd-Quickshell launch removed)',
     !(/\bQt\.RightButton\b/.test(body) && /\bdetach\(\)/.test(body)))
  ok('NO right-click toggle() (single left-click-only contract)',
     !(/\bQt\.RightButton\b/.test(body) && /root\.toggle\(\)/.test(body)))
  // The whole right-button branch must be gone.
  ok('onPressed body has no Qt.RightButton branch',
     !/\bQt\.RightButton\b/.test(body))
}

// --- 2. The detached desktop window (2nd Quickshell) is removed entirely ---
// (omarchy spec: "never start a second Quickshell process for a plugin")
{
  ok('detachProc launcher "quickshell -p <plugin>/Desktop.qml" is REMOVED',
     !/detachProc\.command\s*=\s*\[[^\]]*quickshell[^\]]*Desktop\.qml/.test(SRC))
  ok('no detach() function (desktop-window feature retired per user)',
     !/function detach\(\)/.test(SRC))
  ok('no attach behavior referencing detachProc',
     !/detachProc\.running/.test(SRC))
  ok('no desktop.active flag writes (detach lifecycle retired)',
     !/writeDesktopActive/.test(SRC))
}

// --- 3. The settings PANEL must still be reachable as the sole interaction ---
{
  ok('Panel is loaded via Loader (settings panel mountable on left-click)',
     /Loader\s*\{[\s\S]*?id:\s*panelLoader[\s\S]*?source:\s*Qt\.resolvedUrl\("Panel\.qml"\)/.test(SRC))
  ok('root.toggle() drives the panel open/close (sole click action)',
     /function toggle\(\)/.test(SRC))
}

// --- 4. T-028: bar visualizer must be visible (no 0-width collapse) ---
{
  // The clock sizes WidgetButton via its OWN implicitWidth (a nested spectrum
  // Item drives no implicit width). With text:'' the button collapses to 0 width
  // and the bars render invisible. The fix gives the button a real size from the
  // spectrum geometry and drops anchors.fill:parent so implicitWidth wins.
  ok('WidgetButton sets explicit implicitWidth from spectrum geometry',
     /WidgetButton\s*\{[\s\S]*?implicitWidth:\s*Style\.space\(2\)\s*\+\s*root\.barCount/.test(SRC))
  ok('WidgetButton sets implicitHeight',
     /WidgetButton\s*\{[\s\S]*?implicitHeight:\s*Style\.space\(28\)/.test(SRC))
  ok('WidgetButton does NOT anchors.fill:parent (would override implicitWidth -> 0 width)',
     (() => {
       const header = SRC.match(/WidgetButton\s*\{[\s\S]*?id:\s*button[\s\S]*?bar:\s*root\.bar/)
       return header && !/anchors\.fill:\s*parent/.test(header[0])
     })())
  ok('root still exposes slotW + barCount for the geometry formula',
     /readonly property real slotW:\s*3/.test(SRC) && /property int barCount/.test(SRC))
}

console.log('\nℹ pass ' + passed)

