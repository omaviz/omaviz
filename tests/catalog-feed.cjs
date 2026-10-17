'use strict';
// Real EngineFeed layout transitions through the production Canvas; GPU drawing
// is checked separately by the bounded native probe/capture tests.
const {spawnSync}=require('node:child_process');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const {pathToFileURL}=require('node:url');
const root=path.resolve(__dirname,'..');
const dir=fs.mkdtempSync(path.join(os.tmpdir(),'omaviz-catalog-feed-'));
try {
 const qml=path.join(dir,'shell.qml');
 fs.writeFileSync(qml,`import QtQuick
import Quickshell
import ${JSON.stringify(pathToFileURL(root).href)} as App
ShellRoot {
 id:test
 property int stage:0
 property int ticks:0
 App.EngineFeed {
  id:feed; executable:${JSON.stringify(path.join(root,'bin/omaviz-engine'))}; sourceSpec:"gen=tone"
  siriEnabled:canvas.visual === "Siri"; stringsEnabled:canvas.visual === "Strings"; waveEnabled:true
 }
 FloatingWindow {
  width:320; height:160; visible:true
  App.VisualCanvas {
   id:canvas; anchors.fill:parent; visual:"Siri"
   bands:feed.bands; bandLayout:feed.bandLayout; wave:feed.wave; waveRms:feed.waveRms; silent:feed.silent
  }
 }
 Timer {
  interval:25; running:true; repeat:true
  onTriggered: {
   if(++test.ticks>240) { console.error("CATALOG_FEED_FAILED stage="+test.stage); Qt.quit(); return }
   if(test.stage===0 && feed.bandLayout==="siri" && feed.bands.length===6) { canvas.visual="Orbit"; test.stage=1 }
   else if(test.stage===1 && feed.bandLayout==="" && feed.bands.length===128) { canvas.visual="Strings"; test.stage=2 }
   else if(test.stage===2 && feed.bandLayout==="strings" && feed.bands.length===16) { canvas.visual="PixelWave"; test.stage=3 }
   else if(test.stage===3 && feed.bandLayout==="" && feed.bands.length===128) { canvas.visual="Bokeh"; test.stage=4 }
   else if(test.stage===4 && feed.bands.length===128 && canvas._awake) { canvas.visual="Tunnel"; test.stage=5 }
   else if(test.stage===5 && canvas._awake) { canvas.visual="SolidTunnel"; test.stage=6 }
   else if(test.stage===6 && canvas._awake) { canvas.visual="Cosmos"; test.stage=7 }
   else if(test.stage===7 && canvas._awake) { feed.active=false; test.stage=8 }
   else if(test.stage===8 && !feed.started && !canvas._awake && feed.bands.length===0) {
    console.log("CATALOG_FEED_PASS"); Qt.quit()
   }
  }
 }
}`);
 const result=spawnSync('timeout',['10','quickshell','-p',qml],{
  encoding:'utf8',timeout:13000,
  env:{...process.env,QT_QPA_PLATFORM:'offscreen',QT_QPA_PLATFORMTHEME:'basic',QT_QUICK_BACKEND:'software'}
 });
 const log=result.stdout+result.stderr;
 if(result.error || result.status!==0 || !log.includes('CATALOG_FEED_PASS') || /CATALOG_FEED_FAILED|ReferenceError|TypeError/.test(log))
  throw new Error(result.error?.message || log);
 console.log('PASS: real Siri → Orbit → Strings → Pixel Wave → Bokeh → Tunnel → Solid Tunnel → Cosmos feeds and capture-loss settling');
} finally { fs.rmSync(dir,{recursive:true,force:true}); }
