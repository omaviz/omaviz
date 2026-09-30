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
