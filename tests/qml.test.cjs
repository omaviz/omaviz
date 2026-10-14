"use strict";
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {findQt6Lint,lint}=require('../tools/qml-lint.cjs');
test('all shipped QML passes the Qt 6 syntax gate', t => {
 const binary=findQt6Lint();
 if(!binary) { t.skip('Qt 6 tooling unavailable; required by the native gate'); return; }
 const result=lint(binary);
 assert.ifError(result.error);
 assert.equal(result.status,0,result.stdout+result.stderr);
});
