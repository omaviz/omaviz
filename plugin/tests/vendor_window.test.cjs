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
// T-014 — APPROVED (path correction, ADR-0008 detach-path): the plugin
// imports `qs.Commons` / `qs.Ui` (module form). In detached launches the engine
// resolves those module names to plugin/Commons + plugin/Ui (one level up from
// the earlier mis-placed plugin/qs/). So the vendored tree must live at
// plugin/Commons + plugin/Ui (NOT plugin/qs/), and the plugin files use the
// module-name imports. This is a PATH correction, not a re-vendor — the module
// set is unchanged. Resolves the "unresolvable import .../Commons" warning.
// =====================================================================
{
  // Plugin uses the module-name imports (resolvable by the engine in BOTH the
  // shell mini-bar context and the detached context).
  ok('T-014: Panel.qml imports module qs.Commons / qs.Ui',
     /^import qs\.Commons$/m.test(PANEL) && /^import qs\.Ui$/m.test(PANEL))
  ok('T-014: BarWidget.qml imports module qs.Commons / qs.Ui',
     /^import qs\.Commons$/m.test(BARW) && /^import qs\.Ui$/m.test(BARW))
  ok('T-014: Panel.qml does NOT use the mis-placed relative "qs/Ui"/"qs/Commons" import',
     !/import "qs\/(Ui|Commons)"/.test(PANEL))
  ok('T-014: BarWidget.qml does NOT use the mis-placed relative "qs/Ui"/"qs/Commons" import',
     !/import "qs\/(Ui|Commons)"/.test(BARW))

  // Vendored modules live at the CORRECTED depth: plugin/Commons + plugin/Ui.
  ok('T-014: vendored qs.Commons at corrected path plugin/Commons',
     fs.existsSync(path.join(ROOT, 'Commons', 'qmldir')) &&
     fs.existsSync(path.join(ROOT, 'Commons', 'Color.qml')))
  ok('T-014: vendored qs.Ui at corrected path plugin/Ui',
     fs.existsSync(path.join(ROOT, 'Ui', 'qmldir')) &&
     fs.existsSync(path.join(ROOT, 'Ui', 'KeyboardPanel.qml')))
  // The mis-placed plugin/qs/ tree must be GONE (relocated up one level).
  ok('T-014: mis-placed plugin/qs/ tree removed (relocated to plugin/Commons + plugin/Ui)',
     !fs.existsSync(path.join(ROOT, 'qs')))

  // Vendored Ui files must reference only "../Commons" (no shell qs.*).
  const uiDir = path.join(ROOT, 'Ui')
  const uiFiles = fs.readdirSync(uiDir).filter(f => f.endsWith('.qml'))
  let anyShellImport = false
  for (const f of uiFiles) {
    const s = fs.readFileSync(path.join(uiDir, f), 'utf8')
    if (/import qs\./.test(s)) anyShellImport = true
  }
  ok('T-014: vendored Ui files reference only "../Commons" (no shell qs.*)', !anyShellImport)
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
