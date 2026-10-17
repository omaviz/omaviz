'use strict';
// Bounded GPU evidence for flame motion, audio response, alpha, and desktop scale.
const {spawnSync}=require('node:child_process');
const fs=require('node:fs'),path=require('node:path'),os=require('node:os');
const assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..'),probe=process.argv[2] || path.join(root,'renderer/build/omaviz-render-probe');
const dir=fs.mkdtempSync(path.join(os.tmpdir(),'omaviz-flames-'));
const env={...process.env,QT_QPA_PLATFORM:'offscreen',QT_QPA_PLATFORMTHEME:'basic',QT_QUICK_BACKEND:'rhi',QSG_RHI_BACKEND:'opengl',QSG_RENDER_LOOP:'basic',OMAVIZ_PROBE_FIXED_SIZE:'1',OMAVIZ_PROBE_TIMESTAMPS:'0',OMAVIZ_PROBE_SEQUENCE:'1',OMAVIZ_PROFILE:'1'};
function run(command,args) {
 const r=spawnSync(command,args,{env,encoding:'utf8',timeout:14000});
 if(r.error || r.status!==0) throw new Error(r.error?.message || r.stdout+r.stderr);
 return r.stdout+r.stderr;
}
function metric(...args) {return Number(run('magick',[...args,'-alpha','off','info:']).trim())}
for(const [name,w,h,amp,options,bg] of [
 ['normal',640,360,.45,'','black'],['quiet',640,360,.06,'','black'],
 ['mini',160,32,.45,'','black'],['desktop',3200,900,.45,'','black'],
 ['silence',640,360,.45,'','black'],['mono',640,360,.45,'mono:true;','black'],
 ['mono-light',640,360,.45,'mono:true;monoLight:true;','white'],
 ['alpha',640,360,.45,'','#200040']]) {
 const qml=path.join(dir,name+'.qml'),png=path.join(dir,name+'.png');
 fs.writeFileSync(qml,`import QtQuick
import "file:${root}" as App
Rectangle {
 width:${w};height:${h};color:"${bg}"
 App.VisualCanvas {id:canvas;anchors.fill:parent;visual:"Bars";spikes:true;fire:true;reflect:false;silent:false;bands:Array(128).fill(${amp});${options}}
 ${name==='silence'?'Timer {interval:400;running:true;onTriggered:{canvas.bands=Array(128).fill(0);canvas.silent=true}}':''}
}`);
 const log=run('timeout',['-k','2','10',probe,qml,png,'3']);fs.writeFileSync(path.join(dir,name+'.log'),log);
 assert(!/ReferenceError|TypeError|Error:|Failed to/.test(log),log);
 assert(log.includes('spectrum retained renderer active'),name+' left the flame shader path');
 if(name==='silence') assert(metric(png,'-format','%[fx:maxima]')<.01,'fire did not extinguish');
 else if(name==='mono-light') assert(metric(png,'-format','%[fx:minima]')<.1,'missing dark mono flame');
 else assert(metric(png,'-format','%[fx:maxima]')>.2,name+' invisible');
 if(name==='normal') {
  const delta=metric(path.join(dir,'normal-1.png'),path.join(dir,'normal-3.png'),'-compose','difference','-composite','-format','%[fx:mean]');
  assert(delta>.003,'flames frozen on held input');
 }
 if(name==='mono' || name==='mono-light') assert.equal(metric(png,'-fx','max(abs(r-g),abs(r-b))','-format','%[fx:maxima]'),0);
 if(name==='alpha') assert(metric(png,'-crop','640x25+0+0','+repage','-fx','max(abs(r-32/255),max(abs(g),abs(b-64/255)))','-format','%[fx:maxima]')<1e-6,'transparent upper field altered the background');
 console.log('PASS: flame '+name);
}
const coverage=name=>metric(path.join(dir,name+'.png'),'-fx','max(r,max(g,b))>0.1?1:0','-format','%[fx:mean]');
assert(coverage('normal')>coverage('quiet')*2,'flame height does not follow music energy');
console.log('PASS: stronger input increases flame coverage; captures: '+dir);
