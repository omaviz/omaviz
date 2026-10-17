'use strict';
const {spawnSync}=require('node:child_process');
const fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const {pathToFileURL}=require('node:url');
const root=path.resolve(__dirname,'..'),dir=fs.mkdtempSync(path.join(os.tmpdir(),'omaviz-shuffle-'));
try {
 fs.writeFileSync(path.join(dir,'shell.qml'),`import QtQuick
import Quickshell
import ${JSON.stringify(pathToFileURL(root).href)} as App
ShellRoot {
 id:test
 property int stage:0
 property int changes:0
 property double since:0
 QtObject { id:player; property string identity:"test"; property int uniqueId:1; property string trackTitle:"One"; property string trackArtist:"Artist" }
 QtObject { id:other; property string identity:"other"; property int uniqueId:1; property string trackTitle:"Other"; property string trackArtist:"Artist" }
 App.ShuffleSession { id:shuffle; player:player; onTrackChanged:test.changes++ }
 App.VisualTransition { id:fade; config:({visual:"Siri",shuffle:false}) }
 function fail(message) { console.error("SHUFFLE_FAILED stage="+stage+" "+message); Qt.quit() }
 function next() { stage++; since=Date.now() }
 Timer {
  interval:25; running:true; repeat:true
  onTriggered: {
   let elapsed=Date.now()-test.since
   if(test.stage===0) { shuffle.active=true; test.next() }
   else if(test.stage===1 && elapsed>600) {
    if(test.changes!==0) { test.fail("activation changed visual"); return }
    player.trackTitle="One (metadata update)"; test.next()
   } else if(test.stage===2 && elapsed>600) {
    if(test.changes!==0) { test.fail("same track metadata shuffled"); return }
    player.uniqueId=2; player.trackTitle="Two"; test.next()
   } else if(test.stage===3 && elapsed>600) {
    if(test.changes!==1) { test.fail("track change not exactly once"); return }
    shuffle.player=other; test.next()
   } else if(test.stage===4 && elapsed>600) {
    if(test.changes!==1) { test.fail("player switch shuffled"); return }
    other.uniqueId=2; test.next()
   } else if(test.stage===5 && elapsed>600) {
    if(test.changes!==2) { test.fail("second player track ignored"); return }
    fade.config=({visual:"SolidTunnel",shuffle:true}); test.next()
   } else if(test.stage===6 && elapsed>200) {
    if(fade.presented.visual!=="Siri" || fade.fade>=1 || fade.fade<=0) { test.fail("missing fade-out"); return }
    test.next()
   } else if(test.stage===7 && elapsed>350) {
    if(fade.presented.visual!=="SolidTunnel" || fade.fade>.2) { test.fail("swap did not occur at black"); return }
    test.next()
   } else if(test.stage===8 && elapsed>750) {
    if(fade.fade<.999) { test.fail("fade-in incomplete"); return }
    fade.config=({visual:"Siri",shuffle:false}); test.next()
   } else if(test.stage===9 && elapsed>1300) {
    if(fade.presented.visual!=="Siri" || fade.fade<.999) { test.fail("restore transition failed"); return }
    shuffle.active=false; other.uniqueId=3; test.next()
   } else if(test.stage===10 && elapsed>600) {
    if(test.changes!==2) { test.fail("disabled shuffle emitted"); return }
    console.log("SHUFFLE_PASS"); Qt.quit()
   }
  }
 }
}`);
 const r=spawnSync('timeout',['12','quickshell','-p',path.join(dir,'shell.qml')],{encoding:'utf8',timeout:15000,
  env:{...process.env,QT_QPA_PLATFORM:'offscreen',QT_QPA_PLATFORMTHEME:'',QT_QUICK_BACKEND:'software'}});
 const output=r.stdout+r.stderr;
 if(r.error || r.status!==0 || !output.includes('SHUFFLE_PASS') || /SHUFFLE_FAILED|ReferenceError|TypeError/.test(output)) throw new Error(r.error?.message || output);
 console.log('PASS: real QML track-change debounce, player switching, disable behavior, and fade-out/swap/fade-in with restoration');
} finally {fs.rmSync(dir,{recursive:true,force:true})}
