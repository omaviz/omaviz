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
function harness() {
  let disk = Store.toTOML(Store.defaultConfig());
  const writes = [];
  const root = {_lastWriteText: '', _writingText: '', _writeBusy: false};
  const ctx = vm.createContext({Store, root,
    configFile: {text: () => disk},
    detachConfigWrite: {setText: text => writes.push(text)}});
  root.syncFromConfig = text => {root.config = Store.readConfigFromText(text)};
  for (const name of ['readGuarded', 'noteWrite', 'flushSettings', 'writeVizOptions', 'writeVizOption', 'writeVizOptions3']) {
    vm.runInContext(method(bar, name), ctx);
    root[name] = ctx[name];
  }
  return {root, writes, setDisk: text => {disk = text}};
}

test('rapid selections merge while an async settings write is in flight', () => {
  const {root, writes, setDisk} = harness();
  root.writeVizOption('peaks', false);
  root.writeVizOption('reflect', false);
  root.writeVizOptions3('fire', false, 'bar_color_custom', true, 'bar_color_from', '#112233', 'bar_color_to', '#aabbcc');
  assert.equal(writes.length, 1, 'only one write may be in flight');
  assert.equal(root.config.peaks, false);
  assert.equal(root.config.reflect, false);
  setDisk(writes[0]);
  assert.equal(Store.readConfigFromText(root.readGuarded()).barColorTo, '#aabbcc', 'stale poll must not reset latest choice');
  root._writeBusy = false; // first save completes; flush latest merged state
  root.flushSettings();
  assert.equal(writes.length, 2);
  setDisk(writes[1]);
  root._writeBusy = false;
  const saved = Store.readConfigFromText(root.readGuarded());
  assert.equal(saved.peaks, false);
  assert.equal(saved.reflect, false);
  assert.equal(saved.barColorTo, '#aabbcc');
  assert.equal(root._lastWriteText, '', 'acknowledged writes release the optimistic guard');
  assert.match(writes[1], /peaks = false\n/, 'persist native TOML booleans');
});

test('desktop heartbeats cannot overwrite persistent settings', () => {
  const source = read('Desktop.qml');
  const writes = [];
  const win = {};
  const ctx = vm.createContext({win, desktopState: {setText: text => writes.push(text)}});
  vm.runInContext(method(source, 'setDesktopActive'), ctx);
  ctx.setDesktopActive(true);
  assert.equal(Store.isDesktopActiveFromText(writes[0]), true);
  assert.ok(!writes[0].includes('peaks'));
  ctx.setDesktopActive(false);
  assert.equal(win._closing, true);
  assert.equal(Store.isDesktopActiveFromText(writes[1]), false);
  assert.ok(!source.includes('cfgWrite.setText('), 'desktop settings reader must stay read-only');
});

test('Flame palette is independent of the selected custom/theme palette', () => {
  const color = hex => ({r: parseInt(hex.slice(1,3),16)/255, g: parseInt(hex.slice(3,5),16)/255, b: parseInt(hex.slice(5,7),16)/255});
  const ctx = vm.createContext({Qt: {darker: v => v, lighter: v => v, color},
    barColorCustom: true, colorSync: true,
    barColorFrom: color('#112233'), barColorTo: color('#445566'),
    themeBottom: color('#778899'), themeTop: color('#abcdef'),
    fireColorFrom: color('#be1400'), fireColorTo: color('#fde047')});
  vm.runInContext(method(read('VisualCanvas.qml'), '_rebuildPalette'), ctx);
  ctx._rebuildPalette();
  const first = [...ctx._fireLUT];
  ctx.barColorTo = color('#00ffff');
  ctx.themeTop = color('#ff00ff');
  ctx._rebuildPalette();
  assert.deepEqual([...ctx._fireLUT], first);
  assert.equal(first[0], 'rgba(190,20,0,1)');
  assert.equal(first[100], 'rgba(253,224,71,1)');
});
