'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { load } = require('./helpers.cjs');
const Queue = load('SettingsQueue.js');

test('rapid edits coalesce and stale reads cannot replace an in-flight selection', () => {
  const q = Queue.create('original');
  Queue.edit(q, 'first');
  assert.equal(Queue.next(q), 'first');
  Queue.edit(q, 'second');
  Queue.edit(q, 'latest');
  Queue.loaded(q, 'original');
  assert.equal(Queue.current(q), 'latest');
  assert.equal(Queue.next(q), null);
  Queue.saved(q);
  assert.equal(Queue.next(q), null, 'refresh disk before next write');
  Queue.loaded(q, 'first');
  assert.equal(Queue.next(q), 'latest');
  Queue.saved(q);
  Queue.loaded(q, 'latest');
  assert.equal(Queue.current(q), 'latest');
  assert.equal(Queue.next(q), null);
});

test('save failure rolls back optimistic UI and permits retry after refresh', () => {
  const q = Queue.create('saved');
  Queue.edit(q, 'failed'); Queue.next(q); Queue.failed(q);
  assert.equal(Queue.current(q), 'saved');
  Queue.loaded(q, 'external');
  assert.equal(Queue.current(q), 'external');
  Queue.edit(q, 'retry');
  assert.equal(Queue.next(q), 'retry');
});

test('no-op edits do not write; reverting while saving still persists the revert', () => {
  const q = Queue.create('a');
  assert.equal(Queue.edit(q, 'a'), false);
  assert.equal(Queue.next(q), null);
  Queue.edit(q, 'b'); Queue.next(q); Queue.edit(q, 'a'); Queue.saved(q);
  Queue.loaded(q, 'b');
  assert.equal(Queue.next(q), 'a');
});
