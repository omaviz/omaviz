'use strict';
const {spawnSync} = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'omaviz-components-'));
try {
  for (const name of ['EngineFeed.qml', 'SettingsDocument.qml', 'ModelStore.js', 'SettingsQueue.js'])
    fs.copyFileSync(path.join(__dirname, '..', name), path.join(dir, name));
  fs.copyFileSync(path.join(__dirname, 'qml/shell.qml'), path.join(dir, 'shell.qml'));
  const result = spawnSync('timeout', ['15', 'quickshell', '-p', path.join(dir, 'shell.qml')], {
    encoding: 'utf8', timeout: 20000,
    env: {...process.env, QT_QPA_PLATFORM: 'offscreen', QT_QPA_PLATFORMTHEME: 'basic',
      QT_QUICK_BACKEND: 'software', QT_QUICK_CONTROLS_STYLE: 'Basic',
      OMAVIZ_TEST_CONFIG: path.join(dir, 'config.toml'), OMAVIZ_TEST_ENGINE: path.join(__dirname, '../bin/omaviz-engine')},
  });
  const output = result.stdout + result.stderr;
  if (result.error || result.status !== 0 || !output.includes('COMPONENT_TEST_PASS') || output.includes('COMPONENT_TEST_FAILED')) {
    throw new Error(result.error ? result.error.message : output);
  }
  console.log('PASS: real QML settings I/O, scope restart, rapid re-enable, and shutdown');
} finally { fs.rmSync(dir, {recursive: true, force: true}); }
