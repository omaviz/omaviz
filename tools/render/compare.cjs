'use strict';
// Bounded exports of the real renderer. No production files or user settings
// are changed. Default is software/offscreen; --native uses the host backend.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
const {createHash} = require('node:crypto');
const root = path.resolve(__dirname, '../..');
const native = process.argv.includes('--native');
const outputArg = process.argv.indexOf('--output');
const output = outputArg >= 0 ? path.resolve(process.argv[outputArg + 1]) : fs.mkdtempSync(path.join(os.tmpdir(), 'omaviz-render-output-'));
const config = fs.mkdtempSync(path.join(os.tmpdir(), 'omaviz-render-config-'));
const modes = ['bars', 'flame', 'spikes', 'stacks', 'horizontal', 'mono', 'reflection', 'scope'];
fs.mkdirSync(output, {recursive: true});
try {
  for (const name of ['VisualCanvas.qml', 'Physics.js', 'Palette.js'])
    fs.copyFileSync(path.join(root, name), path.join(config, name));
  fs.copyFileSync(path.join(__dirname, 'shell.qml'), path.join(config, 'shell.qml'));
  const report = {native, output, comparisons: []};
  for (const strategy of ['immediate', 'threaded']) {
    const destination = path.join(output, strategy);
    fs.mkdirSync(destination, {recursive: true});
    const env = {...process.env, OMAVIZ_RENDER_OUTPUT: destination, OMAVIZ_CANVAS_STRATEGY: strategy,
      QSG_INFO: '1', QT_LOGGING_RULES: 'qt.scenegraph.general=true;qt.rhi.*=true'};
    if (!native) Object.assign(env, {QT_QPA_PLATFORM: 'offscreen', QT_QUICK_BACKEND: 'software',
      QT_QPA_PLATFORMTHEME: 'basic', QT_QUICK_CONTROLS_STYLE: 'Basic'});
    const result = spawnSync('timeout', ['12', 'quickshell', '-p', path.join(config, 'shell.qml')],
      {env, encoding: 'utf8', timeout: 15000});
    const log = result.stdout + result.stderr;
    for (const line of log.split('\n')) {
      const image = line.match(/RENDER_IMAGE (\w+) ([A-Za-z0-9+/=]+)/);
      if (image && modes.includes(image[1])) fs.writeFileSync(path.join(destination, `${image[1]}.png`), Buffer.from(image[2], 'base64'));
    }
    fs.writeFileSync(path.join(output, `${strategy}.log`), log.split('\n').filter(line => !line.includes('RENDER_IMAGE ')).join('\n'));
    if (result.error || result.status !== 0 || !log.includes('RENDER_PROBE_PASS') || log.includes('RENDER_PROBE_FAILED'))
      throw new Error(result.error ? result.error.message : log);
  }
  for (const mode of modes) {
    const left = fs.readFileSync(path.join(output, 'immediate', `${mode}.png`));
    const right = fs.readFileSync(path.join(output, 'threaded', `${mode}.png`));
    report.comparisons.push({mode, identicalPng: left.equals(right),
      sha256: createHash('sha256').update(left).digest('hex')});
  }
  fs.writeFileSync(path.join(output, 'report.json'), JSON.stringify(report, null, 2) + '\n');
  console.log(JSON.stringify(report, null, 2));
  if (report.comparisons.some(item => !item.identicalPng)) process.exitCode = 1;
} finally { fs.rmSync(config, {recursive: true, force: true}); }
