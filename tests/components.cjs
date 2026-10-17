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
  const stalled = path.join(dir,'stalled.py');
  fs.writeFileSync(stalled, `#!/usr/bin/python3
import sys,time,signal
signal.signal(signal.SIGTERM, signal.SIG_IGN)
if 'fixture=stall' in sys.argv:
 print('{"bands":[0.8,0.4],"silent":false}',flush=True)
 print('{"wave":[0.6,-0.6]}',flush=True)
while True:
 print('{"wave":[0.6,-0.6]}' if 'fixture=empty' in sys.argv else 'invalid frame',flush=True)
 time.sleep(0.05)
`, {mode:0o755});
  const result = spawnSync('timeout', ['15', 'quickshell', '-p', path.join(dir, 'shell.qml')], {
    encoding: 'utf8', timeout: 20000,
    env: {...process.env, QT_QPA_PLATFORM: 'offscreen', QT_QPA_PLATFORMTHEME: 'basic',
      QT_QUICK_BACKEND: 'software', QT_QUICK_CONTROLS_STYLE: 'Basic',
      OMAVIZ_TEST_STALLED: stalled, OMAVIZ_TEST_CONFIG: path.join(dir, 'config.toml'), OMAVIZ_TEST_ENGINE: path.join(__dirname, '../bin/omaviz-engine')},
  });
  const output = result.stdout + result.stderr;
  if (result.error || result.status !== 0 || !output.includes('COMPONENT_TEST_PASS') || output.includes('COMPONENT_TEST_FAILED')) {
    throw new Error(result.error ? result.error.message : output);
  }
  console.log('PASS: real QML settings I/O, scope restart, stalled/invalid engines, forced termination, recovery, and shutdown');
} finally { fs.rmSync(dir, {recursive: true, force: true}); }
