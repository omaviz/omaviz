'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {load} = require('./helpers.cjs');
const {decodeFrame} = load('ModelStore.js');

test('accepts current and legacy spectrum frames and separate waveform lines', () => {
  assert.deepEqual(decodeFrame('{"bands":[0,0.4,1]}'), {bands:[0,0.4,1], silent:false, source:''});
  assert.deepEqual(decodeFrame('{"wave":[-1,0,1]}'), {wave:[-1,0,1]});
  assert.equal(decodeFrame('{"bands":[],"silent":true,"source":"pipewire"}').silent, true);
});
test('rejects malformed frames before they enter rendering state', () => {
  for (const text of ['null', 'no json', '{}', '{"bands":[null]}', '{"wave":["bad"]}', '{"bands":[1e999]}'])
    assert.equal(decodeFrame(text), null, text);
  assert.equal(decodeFrame(JSON.stringify({bands: Array(4097).fill(0)})), null);
});
test('compact wave identity preserves wakeups when RMS is unchanged', () => {
  assert.deepEqual(decodeFrame('{"wave":[0.1],"wave_serial":2}'), {wave:[0.1], waveSerial:2});
  assert.deepEqual(decodeFrame('{"wave":[0.1],"wave_serial":3}'), {wave:[0.1], waveSerial:3});
  for (const wave_serial of [-1, .5, 2147483648, "bad"])
    assert.deepEqual(decodeFrame(JSON.stringify({wave:[0], wave_serial})), {wave:[0]});
});
test('Strings band layout is explicit and requires sixteen drives', () => {
  const frame = {bands:Array(16).fill(.2), band_layout:'strings'};
  assert.equal(decodeFrame(JSON.stringify(frame)).bandLayout, 'strings');
  assert.equal(decodeFrame(JSON.stringify({...frame, bands:[.2]})).bandLayout, undefined);
  assert.equal(decodeFrame(JSON.stringify({...frame, band_layout:'unknown'})).bandLayout, undefined);
});

test('Siri spectral layout requires six independent layer drives', () => {
  const frame = {bands:[.2,.01,.08,.03,.06,0], band_layout:'siri'};
  assert.equal(decodeFrame(JSON.stringify(frame)).bandLayout, 'siri');
  assert.equal(decodeFrame(JSON.stringify({...frame, bands:[]})).bandLayout, undefined);
});
