// GPU-FREE structural/behavioral regression tests for T-014 (vendoring shell
// modules) + T-018 (Detached window maps) + T-019 (KeyboardPanel anchors.fill).
//
// These assert the invariants the ADRs require by parsing source — no Qt/GPU.
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
// T-014 — shell modules vendored into the plugin; no runtime qs.* import
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

  // The plugin must NOT import the shell-provided modules at runtime.
  ok('T-014: Panel.qml does not import qs.Commons / qs.Ui (shell modules)',
     !/import qs\.(Commons|Ui)/.test(PANEL))
  ok('T-014: BarWidget.qml does not import qs.Commons / qs.Ui (shell modules)',
     !/import qs\.(Commons|Ui)/.test(BARW))
  // It must instead import the vendored copies (relative dir imports).
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
  ok('T-019: plugin/qs/Ui/KeyboardPanel exists (vendored surface used)',
     fs.existsSync(path.join(ROOT, 'qs', 'Ui', 'KeyboardPanel.qml')))
}

// =====================================================================
// T-018 — Detached window root resolves to Quickshell.Window (QsWindow)
// =====================================================================
{
  // Root must be Quickshell.Window (unambiguous), not bare Window (QtQuick).
  ok('T-018: Desktop.qml root is Quickshell.Window (QsWindow), not bare Window',
     /^Quickshell\.Window\s*\{/m.test(DESK))
  ok('T-018: Desktop.qml has no ambiguous bare "Window {" root',
     !/^\s*Window\s*\{/m.test(DESK))
  ok('T-018: Desktop.qml imports Quickshell (provides Window)',
     /import Quickshell(\n|\r|\s)/.test(DESK))
}

console.log('\nℹ vendor_window tests ' + passed)
console.log('ℹ pass ' + passed)
console.log('ℹ fail 0')
