'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const read = name => fs.readFileSync(path.join(__dirname, '..', name), 'utf8');
const storeContext = vm.createContext({});
vm.runInContext(read('ModelStore.js').replace(/^\.pragma library\s*/, ''), storeContext);
const Store = storeContext;
const bar = read('BarWidget.qml');
function method(source, name) {
  const match = source.match(new RegExp('^  function ' + name + '\\([^]*?^  }', 'm'));
  assert.ok(match, `missing ${name}`);
  return match[0];
}
test('desktop heartbeats cannot overwrite persistent settings', () => {
  const source = read('Desktop.qml');
  const writes = [];
  const win = {};
  const ctx = vm.createContext({win, bridge: {running: true}, bridgeRetryTimer: {stop() {}}, desktopState: {setText: text => writes.push(text)}});
  vm.runInContext(method(source, 'setDesktopActive'), ctx);
  ctx.setDesktopActive(true);
  assert.equal(Store.isDesktopActiveFromText(writes[0]), true);
  assert.ok(!writes[0].includes('peaks'));
  ctx.setDesktopActive(false);
  assert.equal(win._closing, true);
  assert.equal(Store.isDesktopActiveFromText(writes[1]), false);
  assert.ok(!source.includes('cfgWrite.setText('), 'desktop settings reader must stay read-only');
});


test('theme snapshot cannot replace saved settings before initial config load', () => {
  let writes = 0;
  const root = {_ready: true, _configReady: false, config: {}, colorHex: () => '#112233',
    readGuarded: () => { throw new Error('read before config is ready'); },
    writeVizOptions3: () => { writes++; }};
  const ctx = vm.createContext({root, settingsDocument: {ready:false}, Color: {accent: '#112233'}});
  vm.runInContext(method(read('BarWidget.qml'), 'snapThemeColors'), ctx);
  ctx.snapThemeColors();
  assert.equal(writes, 0);
});


test('color modes are exclusive and preserve custom palette values', () => {
  const calls = [];
  const root = {writeVizMap: value => calls.push(value)};
  const ctx = vm.createContext({root});
  vm.runInContext(method(bar, 'setColorMode'), ctx);
  for (const mode of ['Theme', 'Custom', 'Artwork', 'Flame']) {
    assert.equal(ctx.setColorMode(mode), true);
    const opts = calls.at(-1);
    assert.equal(opts.fire, mode === 'Flame');
    assert.equal(opts.bar_color_custom, mode === 'Custom');
    assert.equal(opts.artwork_colors, mode === 'Artwork');
    assert.equal('bar_color_from' in opts, false);
  }
  assert.equal(ctx.setColorMode('invalid'), false);
  assert.equal(calls.length, 4);
});



// SettingsQueue and the bounded real-QML component harness cover asynchronous
// writes and capture transitions shared by both surfaces.
test('waveform selections and multi-stop palettes survive settings round trips', () => {
  for (const visual of ['Bars','Waves','Strings','Siri']) {
    const config = {...Store.defaultConfig(), visual, barColorMiddleEnabled:true,
      barColorMiddle:'#12abcd', artworkColors:true};
    const saved = Store.readConfigFromText(Store.toTOML(config));
    assert.equal(saved.visual,visual);
    assert.equal(saved.barColorMiddle,'#12abcd');
    assert.equal(saved.barColorMiddleEnabled,true);
    assert.equal(saved.artworkColors,true);
  }
});
