'use strict';
// GPU regression: the shipped palette action must remove the cached blur's
// pixels, not merely change its configuration flag.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {pathToFileURL} = require('node:url');
const {spawnSync} = require('node:child_process');
const repo = path.resolve(__dirname, '..');
const runtime = process.env.OMAVIZ_RENDER_ROOT || repo;
const probe = process.argv[2] || path.join(repo, 'renderer/build/omaviz-render-probe');
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'omaviz-artwork-'));
const desktop = fs.readFileSync(path.join(runtime, 'Desktop.qml'), 'utf8');
const start = desktop.indexOf('      Loader {', desktop.indexOf('// FastBlur caches:'));
const end = desktop.indexOf('      // Cover-derived', start);
assert.ok(start >= 0 && end > start, 'production artwork Loader missing');
const action = fs.readFileSync(path.join(runtime, 'BarWidget.qml'), 'utf8')
  .match(/^  function setColorMode\([^]*?^  }/m)?.[0];
assert.ok(action, 'production palette action missing');
fs.copyFileSync(path.join(runtime, 'ModelStore.js'), path.join(dir, 'ModelStore.js'));
const scene = path.join(dir, 'scene.qml');
const image = path.join(dir, 'result.png');
fs.writeFileSync(scene, `import QtQuick
import Qt5Compat.GraphicalEffects
import "file:${path.join(runtime,'native')}" as Native
import "ModelStore.js" as Store
Rectangle {
 id:win; width:640; height:360; color:"#0c0c12"
 property var vizConfig: ({visual:"Bars",artwork:false})
 property string configText: ${JSON.stringify('[desktop]\nvisual = "Bars"\n')}
 property string trackArt: ${JSON.stringify(pathToFileURL(path.join(repo, 'docs/screenshots/marketing/Spectrum.png')).href)}
 Native.ArtworkPalette { id:coverPalette; source:win.trackArt }
 readonly property bool hasArt: trackArt!=="" && vizConfig.artwork!==false
 readonly property bool immersiveArt:false
 function writeVizMap(options) {
  configText=Store.patchSettings(configText,"desktop",options)
  vizConfig=Store.readConfigFromText(configText)
  console.log("ARTWORK_STATE",vizConfig.colorMode,vizConfig.artwork)
 }
 ${action.replaceAll('root.', 'win.')}
 ${desktop.slice(start, end)}
 Timer { interval:100;running:true;onTriggered:win.setColorMode("Artwork") }
 Timer { interval:2350;running:true;onTriggered:win.setColorMode("Theme") }
}`);
const result = spawnSync('timeout', ['-k', '2', '10', probe, scene, image, '3'], {
  encoding:'utf8', timeout:13000,
  env:{...process.env, QT_QPA_PLATFORM:'offscreen', QT_QPA_PLATFORMTHEME:'basic',
    QT_QUICK_BACKEND:'rhi', QSG_RHI_BACKEND:'opengl', QSG_RENDER_LOOP:'basic',
    OMAVIZ_PROBE_FIXED_SIZE:'1', OMAVIZ_PROBE_TIMESTAMPS:'0', OMAVIZ_PROBE_SEQUENCE:'1'},
});
const log = result.stdout + result.stderr;
fs.writeFileSync(path.join(dir, 'render.log'), log);
assert.ifError(result.error);
assert.equal(result.status, 0, log);
assert.match(log, /ARTWORK_STATE Artwork true/);
assert.match(log, /ARTWORK_STATE Theme false/);
assert.doesNotMatch(log, /ReferenceError|TypeError|Failed to compile shader|Failed to build graphics pipeline/);
function metric(file, expression) {
  const value = spawnSync('magick', [file, '-alpha', 'off', '-colorspace', 'gray',
    '-format', `%[fx:${expression}]`, 'info:'], {encoding:'utf8', timeout:10000});
  assert.ifError(value.error);
  assert.equal(value.status, 0, value.stderr);
  return Number(value.stdout);
}
assert.ok(metric(image.replace('.png', '-1.png'), 'standard_deviation') > .0001,
  'artwork was never rendered; an empty before image cannot prove cache removal');
assert.equal(metric(image, 'maxima-minima'), 0, 'artwork pixels survived deselection');
console.log('PASS: production Artwork → Theme action removes every cached backdrop pixel; captures: ' + dir);
