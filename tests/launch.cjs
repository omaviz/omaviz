'use strict';
// Exercise the actual app entry point with isolated settings and command stubs.
const {spawnSync} = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'omaviz-launch-'));
try {
  const runtime = path.join(dir, 'runtime');
  const bin = path.join(dir, 'bin');
  fs.mkdirSync(runtime); fs.mkdirSync(bin);
  fs.mkdirSync(path.join(dir, 'omaviz'));
  for (const name of ['Launch.qml','SettingsDocument.qml','SettingsQueue.js','ModelStore.js'])
    fs.copyFileSync(path.join(root,name), path.join(runtime,name));
  const log = path.join(dir, 'commands.log');
  fs.writeFileSync(path.join(bin,'omarchy'), `#!/usr/bin/python3
import os,tomllib
from pathlib import Path
config=tomllib.loads((Path(os.environ['XDG_CONFIG_HOME'])/'omaviz/config.toml').read_text())
assert config['desktop']['enabled'] is True
with open(os.environ['OMAVIZ_LAUNCH_LOG'],'a') as f:f.write('enable '+ ' '.join(os.sys.argv[1:])+'\\n')
`, {mode:0o755});
  fs.writeFileSync(path.join(bin,'quickshell'), '#!/bin/sh\nprintf "desktop %s\\n" "$*" >> "$OMAVIZ_LAUNCH_LOG"\n', {mode:0o755});
  const quickshell = spawnSync('which',['quickshell'],{encoding:'utf8'}).stdout.trim();
  for (const enabled of [false,true]) {
    fs.writeFileSync(log,'');
    fs.writeFileSync(path.join(dir,'omaviz/config.toml'), `[desktop]\nenabled = ${enabled}\nvisual = "PixelWave"\n[keep]\nvalue = 42\n`);
    const result = spawnSync('timeout',['10',quickshell,'-p',path.join(runtime,'Launch.qml')], {
      encoding:'utf8', timeout:12000,
      env:{...process.env, XDG_CONFIG_HOME:dir, PATH:bin+':'+process.env.PATH,
        OMAVIZ_LAUNCH_LOG:log, QT_QPA_PLATFORM:'offscreen',QT_QPA_PLATFORMTHEME:'basic',QT_QUICK_BACKEND:'software'}
    });
    assert.equal(result.status,0,result.stdout+result.stderr);
    assert.doesNotMatch(result.stdout+result.stderr,/ReferenceError|TypeError|could not enable/);
    // Detached launch may finish just after the entry point exits.
    spawnSync('sleep',['0.15']);
    const commands = fs.readFileSync(log,'utf8').trim().split('\n');
    assert.equal(commands[0],'enable plugin enable org.omaviz.visualizer');
    assert.equal(commands[1],`desktop -n -p ${runtime}/Desktop.qml`);
    assert.equal(commands.length,2);
    const text=fs.readFileSync(path.join(dir,'omaviz/config.toml'),'utf8');
    assert.match(text,/enabled = true/); assert.match(text,/visual = "PixelWave"/); assert.match(text,/value = 42/);
  }
  console.log('PASS: app launch resumes saved settings before enabling plugin, preserves options, and requests one desktop instance');
} finally { fs.rmSync(dir,{recursive:true,force:true}); }
