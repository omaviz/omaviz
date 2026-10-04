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

test('bar capture pauses behind the detached window and resumes for preview or mini', () => {
  const spectrumProc = {running: true};
  let retriesStopped = 0;
  const root = {vizEnabled: true, desktopLive: false, opened: false, _intentionalFeedStop: false};
  const ctx = vm.createContext({root, spectrumProc, bridgeRetryTimer: {stop: () => {retriesStopped++}}});
  for (const name of ['wantsFeed', 'syncBarFeed']) {
    vm.runInContext(method(bar, name), ctx);
    root[name] = ctx[name];
  }
  root.desktopLive = true;
  root.syncBarFeed();
  assert.equal(spectrumProc.running, false);
  assert.equal(root._intentionalFeedStop, true);
  assert.equal(retriesStopped, 1);
  root.opened = true;
  root.syncBarFeed();
  assert.equal(spectrumProc.running, true, 'opening settings must restore the live preview');
  root.opened = false;
  root.desktopLive = false;
  root.syncBarFeed();
  assert.equal(spectrumProc.running, true, 'closing the desktop must restore the mini');
});

test('Flame palette inputs stay independent of the custom/theme palette', () => {
  const renderer = read('VisualCanvas.qml');
  assert.match(renderer, /fireBottom: cv\.fireColorFrom, fireTop: cv\.fireColorTo/);
  const native = read('renderer/geometry.cpp');
  assert.ok(native.includes('mix(fireBottom,QColor(255,130,10)'));
  assert.ok(native.includes('mix(quarter,fireTop,'));
});


test('theme snapshot cannot replace saved settings before initial config load', () => {
  let writes = 0;
  const root = {_ready: true, _configReady: false, config: {}, colorHex: () => '#112233',
    readGuarded: () => { throw new Error('read before config is ready'); },
    writeVizOptions3: () => { writes++; }};
  const ctx = vm.createContext({root, Color: {accent: '#112233'}});
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


test('desktop applies loaded settings, pauses without closing, and restarts for waveform feed', () => {
  const bridge = {running: true};
  const win = {_lastCfgText: '', _lastScope: false, _claimed: true, _closing: false, _restarting: false};
  const ctx = vm.createContext({win, bridge, Store, bridgeRetryTimer: {stop() {}}});
  vm.runInContext(method(read('Desktop.qml'), 'applySettings'), ctx);
  ctx.applySettings('[desktop]\nvisual = "Siri"\nenabled = true');
  assert.equal(win.vizConfig.visual, 'Siri');
  assert.equal(bridge.running, false);
  assert.equal(win._restarting, true);
  win._restarting = false; bridge.running = true;
  ctx.applySettings('[desktop]\nvisual = "Siri"\nenabled = false');
  assert.equal(bridge.running, false);
  assert.equal(win._closing, false);
  ctx.applySettings('[desktop]\nvisual = "Siri"\nenabled = true');
  assert.equal(bridge.running, true);
});

test('playback stays on the controlled player and supports pause then play', () => {
  let pauses=0, plays=0;
  const player={canControl:true, canPause:true, canPlay:true, isPlaying:true,
    pause(){pauses++; this.isPlaying=false}, play(){plays++; this.isPlaying=true}};
  const win={activePlayer:player};
  const ctx=vm.createContext({win});
  vm.runInContext(method(read('Desktop.qml'),'togglePlayback'),ctx);
  ctx.togglePlayback(); ctx.togglePlayback();
  assert.equal(pauses,1); assert.equal(plays,1); assert.equal(win.preferredPlayer,player);
});

test('Exit stops capture and requests desktop close independently of settings saves', () => {
  let stopped=0, closed=0, delayed=0, lease=null;
  const root={_exitRequested:false, close(){closed++}, writeDesktopActive(v){lease=v}};
  const spectrumProc={running:true};
  const ctx=vm.createContext({root,spectrumProc,bridgeRetryTimer:{stop(){stopped++}},exitDelay:{restart(){delayed++}}});
  vm.runInContext(method(bar,'requestExit'),ctx);
  ctx.requestExit(); ctx.requestExit();
  assert.equal(spectrumProc.running,false);
  assert.equal(lease,false); assert.equal(stopped,1); assert.equal(closed,1); assert.equal(delayed,1);
});
