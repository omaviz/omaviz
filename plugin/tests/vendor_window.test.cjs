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
// T-014 — GO (correction): vendor qs.Ui/qs.Commons into plugin/qs/{Ui,Commons}
// so the STANDALONE detached Desktop.qml launch resolves qs.* (it loads
// BarWidget.qml/Panel.qml which import qs.*). The mini bar resolves qs.* fine
// in the shell; vendoring does not break it (copies are verbatim). Plugin files
// must import the vendored relative dirs, NOT the shell-provided qs.*.
// =====================================================================
{
  const vendoredUi = fs.existsSync(path.join(ROOT, 'qs', 'Ui', 'KeyboardPanel.qml'))
    && fs.existsSync(path.join(ROOT, 'qs', 'Ui', 'Panel.qml'))
    && fs.existsSync(path.join(ROOT, 'qs', 'Ui', 'ButtonGroup.qml'))
    && fs.existsSync(path.join(ROOT, 'qs', 'Ui', 'ToggleSwitch.qml'))
    && fs.existsSync(path.join(ROOT, 'qs', 'Ui', 'PanelSlider.qml'))
    && fs.existsSync(path.join(ROOT, 'qs', 'Ui', 'PanelSectionHeader.qml'))
    && fs.existsSync(path.join(ROOT, 'qs', 'Ui', 'PanelSeparator.qml'))
    && fs.existsSync(path.join(ROOT, 'qs', 'Ui', 'WidgetButton.qml'))
    && fs.existsSync(path.join(ROOT, 'qs', 'Ui', 'BorderSurface.qml'))
    && fs.existsSync(path.join(ROOT, 'qs', 'Ui', 'BorderOverlay.qml'))
    && fs.existsSync(path.join(ROOT, 'qs', 'Ui', 'Button.qml'))
    && fs.existsSync(path.join(ROOT, 'qs', 'Ui', 'PanelKeyCatcher.qml'))
    && fs.existsSync(path.join(ROOT, 'qs', 'Ui', 'PanelController.qml'))
  const vendoredCommons = fs.existsSync(path.join(ROOT, 'qs', 'Commons', 'Color.qml'))
    && fs.existsSync(path.join(ROOT, 'qs', 'Commons', 'Style.qml'))
    && fs.existsSync(path.join(ROOT, 'qs', 'Commons', 'Util.qml'))
    && fs.existsSync(path.join(ROOT, 'qs', 'Commons', 'Border.qml'))
    && fs.existsSync(path.join(ROOT, 'qs', 'Commons', 'BorderGeometry.js'))
  ok('T-014: qs.Ui types vendored into plugin/qs/Ui', vendoredUi)
  ok('T-014: qs.Commons singletons vendored into plugin/qs/Commons', vendoredCommons)

  ok('T-014: Panel.qml does NOT import shell qs.Commons / qs.Ui',
     !/^import qs\.(Commons|Ui)$/m.test(PANEL))
  ok('T-014: BarWidget.qml does NOT import shell qs.Commons / qs.Ui',
     !/^import qs\.(Commons|Ui)$/m.test(BARW))
  ok('T-014: Panel.qml imports vendored qs/Ui + qs/Commons',
     /import "qs\/Ui"/.test(PANEL) && /import "qs\/Commons"/.test(PANEL))
  ok('T-014: BarWidget.qml imports vendored qs/Ui + qs/Commons',
     /import "qs\/Ui"/.test(BARW) && /import "qs\/Commons"/.test(BARW))

  // Vendored Ui files must not reach back to the shell module either.
  const uiDir = path.join(ROOT, 'qs', 'Ui')
  const uiFiles = fs.readdirSync(uiDir).filter(f => f.endsWith('.qml'))
  let anyShellImport = false
  for (const f of uiFiles) {
    const s = fs.readFileSync(path.join(uiDir, f), 'utf8')
    if (/import qs\./.test(s)) anyShellImport = true
  }
  ok('T-014: vendored qs/Ui files reference only "../Commons" (no shell qs.*)', !anyShellImport)
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
