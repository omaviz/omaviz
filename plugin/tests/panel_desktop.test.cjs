// GPU-FREE structural/behavioral regression tests for T-014 (settings-panel
// popup invisible) and T-015 (detached desktop window blank + no audio).
//
// These parse the QML/engine source and assert the invariants the ADRs require.
// They never instantiate Qt or launch a GPU/Wayland surface, so they run under
// node / cargo without any shell. (Cf. barwidget.test.cjs pattern.)
//
// Run:  node tests/panel_desktop.test.cjs
const assert = require('assert')
const fs = require('fs')
const path = require('path')

const PANEL = fs.readFileSync(path.join(__dirname, '..', 'Panel.qml'), 'utf8')
const DESKTOP = fs.readFileSync(path.join(__dirname, '..', 'Desktop.qml'), 'utf8')

let passed = 0
function ok(name, cond) {
  assert.ok(cond, name)
  passed++
  console.log('  ok - ' + name)
}

// =====================================================================
// T-014 — settings-panel popup must have a valid anchor even before injection
// =====================================================================
{
  // The KeyboardPanel anchor/owner must use a fallback chain so the popup is
  // never anchored to a null item on first show (root cause of invisible panel).
  ok('T-014: KeyboardPanel anchorItem uses fallback chain (not bare root.anchorItem)',
     /anchorItem:\s*root\.anchorItem\s*\|\|\s*root\.bar\s*\|\|\s*root\b/.test(PANEL))
  ok('T-014: KeyboardPanel owner uses fallback chain',
     /owner:\s*root\.hostWidget\s*\|\|\s*root\.bar\s*\|\|\s*root\b/.test(PANEL))

  // The open state must be forwarded from the base controller locally
  // (_ctrlOpen) and bound to the surface, not a bare inherited root.opened.
  ok('T-014: Panel exposes a locally-forwarded controller-open property (_ctrlOpen)',
     /_ctrlOpen/.test(PANEL))
  ok('T-014: KeyboardPanel.open binds to the forwarded _ctrlOpen (not bare root.opened)',
     /open:\s*root\._ctrlOpen/.test(PANEL))
  ok('T-014: bare KeyboardPanel.open: root.opened is removed (no silent dead binding)',
     !/open:\s*root\.opened\s*\n/.test(PANEL))
}

// =====================================================================
// T-015 — detached window: per-frame bands push + engine stderr surfaced
// =====================================================================
{
  // Bands must be pushed to the GL item on EVERY parsed frame, not only via a
  // one-shot Binding (secondary root cause: fragile single Binding).
  ok('T-015: Desktop onRead pushes bands to the GL item per frame (desktopViz.item.bands =)',
     /desktopViz\.item\.bands\s*=/.test(DESKTOP))
  ok('T-015: Desktop onRead pushes silent to the GL item per frame (desktopViz.item.silent =)',
     /desktopViz\.item\.silent\s*=/.test(DESKTOP))

  // Engine diagnostics must be surfaced, not discarded (primary root cause was
  // silent: the desktop window dropped the engine's stderr).
  ok('T-015: Desktop bridge surfaces engine stderr (stderr handler present)',
     /stderr:/.test(DESKTOP))
}

console.log('\nℹ panel_desktop tests ' + passed)
console.log('ℹ pass ' + passed)
console.log('ℹ fail 0')
