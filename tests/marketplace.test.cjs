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

const {submit} = require('../tools/release/marketplace.cjs');
const identity = {id: 'org.omaviz.visualizer', repository: 'omaviz/omaviz', commit: 'b'.repeat(40)};
function apiSequence(responses) {
  const calls = [];
  const gh = args => {
    calls.push(args);
    assert.ok(responses.length, 'unexpected additional GitHub request');
    const next = responses.shift();
    if (next instanceof Error) throw next;
    return next;
  };
  return {gh, calls};
}
test('stale releases never create marketplace issues, including a HEAD change during lookup', () => {
  for (const responses of [['c'.repeat(40)], [identity.commit, '[[]]', 'c'.repeat(40)]]) {
    const api = apiSequence(responses);
    assert.deepEqual(submit(identity, api.gh), {status: 'stale'});
    assert.ok(api.calls.every(args => args[0] === 'api'));
  }
});
test('reruns reuse closed requests instead of creating duplicate issues', () => {
  const url = 'https://github.com/omacom/omarchy-plugin-marketplace/issues/123';
  const api = apiSequence([identity.commit, JSON.stringify([[{state: 'closed', body: request(identity).body, html_url: url}]])]);
  assert.deepEqual(submit(identity, api.gh), {status: 'existing', url});
  assert.equal(api.calls.length, 2);
});
test('fresh release creates one request for the exact verified commit', () => {
  const url = 'https://github.com/omacom/omarchy-plugin-marketplace/issues/124';
  const api = apiSequence([identity.commit, '[[]]', identity.commit, url]);
  assert.deepEqual(submit(identity, api.gh), {status: 'created', url});
  assert.deepEqual(api.calls.at(-1), ['issue', 'create', '--repo', 'omacom/omarchy-plugin-marketplace', '--title', request(identity).title, '--body', request(identity).body]);
});
test('API failures stop submission and remain visible to the release workflow', () => {
  const api = apiSequence([identity.commit, new Error('permission denied')]);
  assert.throws(() => submit(identity, api.gh), /permission denied/);
  assert.equal(api.calls.length, 2);
});
