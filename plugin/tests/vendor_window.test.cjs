// GPU-FREE structural/behavioral regression tests for the T-014/018/019
// correction wave. T-014 import-cause is HELD (architect live-load proved the
// qs.Commons warning is non-fatal: config still "Configuration Loaded"). So the
// plugin must NOT vendor qs modules nor rewire imports — Panel.qml/BarWidget.qml
// keep the SHELL-provided `import qs.Commons` / `import qs.Ui`. The vendored
// plugin/qs/ tree (if present on disk) is intentionally left untracked/unused.
//
// T-019 (ADR-0011) and T-015 (ADR-0009) are implemented and asserted here / in
// panel_desktop.test.cjs. T-018 is WITHDRAWN (bare Window maps fine).
//
// Run:  node tests/vendor_window.test.cjs
const assert = require('assert')
const fs = require('fs')
const path = require('path')

const ROOT = path.join(__dirname, '..')
const PANEL = fs.readFileSync(path.join(ROOT, 'Panel.qml'), 'utf8')
const BARW = fs.readFileSync(path.join(ROOT, 'BarWidget.qml'), 'utf8')
const DESK = fs.readFileSync(path.join(ROOT, 'Desktop.qml'), 'utf8')

let passed = 0
function ok(name, cond) {
  assert.ok(cond, name)
  passed++
  console.log('  ok - ' + name)
}

// =====================================================================
// T-014 — HELD: do NOT vendor qs modules / rewire imports.
// Plugin keeps shell-provided `import qs.Commons` / `import qs.Ui`.
// =====================================================================
{
  ok('T-014(HELD): Panel.qml still uses shell import qs.Commons',
     /^import qs\.Commons$/m.test(PANEL))
  ok('T-014(HELD): Panel.qml still uses shell import qs.Ui',
     /^import qs\.Ui$/m.test(PANEL))
  ok('T-014(HELD): BarWidget.qml still uses shell import qs.Commons',
     /^import qs\.Commons$/m.test(BARW))
  ok('T-014(HELD): BarWidget.qml still uses shell import qs.Ui',
     /^import qs\.Ui$/m.test(BARW))
  // And must NOT use the vendored relative dir imports.
  ok('T-014(HELD): Panel.qml does NOT import vendored "qs/Ui"/"qs/Commons"',
     !/import "qs\/(Ui|Commons)"/.test(PANEL))
  ok('T-014(HELD): BarWidget.qml does NOT import vendored "qs/Ui"/"qs/Commons"',
     !/import "qs\/(Ui|Commons)"/.test(BARW))
}

// =====================================================================
// T-019 — KeyboardPanel.anchors.fill removed (it's a PanelWindow)
// =====================================================================
{
  // A PanelWindow (KeyboardPanel) has no `anchors` property, so a DIRECT-child
  // `anchors.fill: parent` aborts construction (ADR-0011). Nested items inside
  // the panel (PanelKeyCatcher, preview Rectangle/VisualCanvas) legitimately use
  // anchors.fill — so only assert the line is absent as a direct child of
  // KeyboardPanel (i.e. before any nested '{' opens).
  const block = PANEL.match(/KeyboardPanel\s*\{[^{}]*/)
  const directChildHasFill = block ? /anchors\.fill:\s*parent/.test(block[0]) : false
  ok('T-019: KeyboardPanel has NO direct-child anchors.fill: parent (PanelWindow has no anchors)',
     !directChildHasFill)
}

// =====================================================================
// T-018 — WITHDRAWN: architect empirically proved a bare `Window {` DOES map
// under Hyprland/Quickshell. No window-type change is applied.
// =====================================================================
{
  ok('T-018(WITHDRAWN): Desktop.qml root is bare Window { (no window-type change applied)',
     /^Window\s*\{/m.test(DESK))
  ok('T-018(WITHDRAWN): Desktop.qml does NOT use Quickshell.Window (change withdrawn)',
     !/Quickshell\.Window\s*\{/m.test(DESK))
}

console.log('\nℹ vendor_window tests ' + passed)
console.log('ℹ pass ' + passed)
console.log('ℹ fail 0')
