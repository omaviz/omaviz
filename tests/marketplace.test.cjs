'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {request} = require('../tools/release/marketplace.cjs');
test('marketplace link and issue body refer to the same exact plugin commit', () => {
  const commit = 'a'.repeat(40);
  const data = request({id: 'org.omaviz.visualizer', repository: 'omaviz/omaviz', commit});
  const url = new URL(data.url);
  assert.equal(url.searchParams.get('target-commit'), commit);
  assert.equal(url.searchParams.get('verification-action'), 'Verify and publish a newer upstream commit');
  assert.equal(url.searchParams.get('repository'), 'https://github.com/omaviz/omaviz');
  assert.match(data.body, new RegExp(`### Target commit\\n\\n${commit}\\n`));
  assert.ok(data.body.includes(data.marker));
});
test('marketplace requests reject ambiguous commits and malformed repository fields', () => {
  for (const override of [{commit: 'master'}, {repository: 'https://github.com/omaviz/omaviz'}, {id: 'bad\nfield'}])
    assert.throws(() => request({id: 'org.omaviz.visualizer', repository: 'omaviz/omaviz', commit: 'a'.repeat(40), ...override}));
});
