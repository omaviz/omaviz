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

// --- 4. T-028 (corrected): bar visualizer must render via WidgetButton.text ---
{
  // WidgetButton ONLY paints its `text` property — a nested Item/Repeater is
  // never rendered (and text:'' collapses the button to ~12px so the spectrum
  // spills outside the clip and vanishes). The fix renders the live spectrum as
  // a unicode block-char ticker in WidgetButton.text.
  ok('WidgetButton.text is bound to root.spectrumText() (unicode ticker)',
     /WidgetButton\s*\{[\s\S]*?text:\s*root\.spectrumText\(\)/.test(SRC))
  ok('root.spectrumText() maps bands to block glyphs [space,▁▂▃▄▅▆▇█] + idle ♪',
     /readonly property string BLOCKS:\s*" ▁▂▃▄▅▆▇█"/.test(SRC)
       && /function spectrumText\(\)/.test(SRC)
       && /chars\.charAt\(level\)/.test(SRC)
       && /return "♪"/.test(SRC))
  ok('nested Item/Repeater spectrum REMOVED (WidgetButton only paints text)',
     !/Repeater\s*\{/.test(SRC) && !/id:\s*bar\s*\n/.test(SRC))
  ok('WidgetButton does NOT anchors.fill:parent (text drives its own size)',
     (() => {
       const header = SRC.match(/WidgetButton\s*\{[\s\S]*?id:\s*button[\s\S]*?bar:\s*root\.bar/)
       return header && !/anchors\.fill:\s*parent/.test(header[0])
     })())
  ok('root still exposes barCount for the ticker column count',
     /property int barCount/.test(SRC))
}

console.log('\nℹ pass ' + passed)

