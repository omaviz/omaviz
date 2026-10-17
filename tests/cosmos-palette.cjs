'use strict';
// Freeze travel, change only the palette, and compare foreground stars/core.
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const assert=require('node:assert/strict');
const {spawnSync}=require('node:child_process');
const root=path.resolve(__dirname,'..');
const runtime=process.env.OMAVIZ_RENDER_ROOT || root;
const probe=process.argv[2] || path.join(root,'renderer/build/omaviz-render-probe');
const dir=fs.mkdtempSync(path.join(os.tmpdir(),'omaviz-cosmos-palette-'));
function run(command,args,options={}) {
 const r=spawnSync(command,args,{timeout:12000,...options});
 assert.ifError(r.error);
 assert.equal(r.status,0,String(r.stdout)+String(r.stderr));
 return r.stdout;
}
const qml=path.join(dir,'palette.qml');
fs.writeFileSync(qml,`import QtQuick
import ${JSON.stringify('file:'+runtime)} as App
Rectangle { width:640; height:360; color:"black"
 App.VisualCanvas { id:canvas; anchors.fill:parent; visual:"Cosmos"; silent:false;
  waveRms:.06; bands:Array(128).fill(.25); barColorCustom:true;
  barColorFrom:"#ff3020"; barColorTo:barColorFrom }
 Timer { interval:1000;running:true;onTriggered:canvas._awake=false }
 Timer { interval:2400;running:true;onTriggered:canvas.barColorFrom="#2050ff" }
}`);
run('timeout',['-k','2','8',probe,qml,path.join(dir,'palette.png'),'4'],{
 env:{...process.env,QT_QPA_PLATFORM:'offscreen',QT_QPA_PLATFORMTHEME:'basic',
  QT_QUICK_BACKEND:'rhi',QSG_RHI_BACKEND:'opengl',QSG_RENDER_LOOP:'basic',
  OMAVIZ_PROBE_FIXED_SIZE:'1',OMAVIZ_PROBE_TIMESTAMPS:'0',OMAVIZ_PROBE_SEQUENCE:'1'}
});
// The final capture leaves time for the changed palette to reach the GPU.
const [red,blue]=['palette-1.png','palette.png'].map(name=>run('magick',[path.join(dir,name),'-depth','8','rgb:-']));
let samples=0,starDelta=0,redCore=[0,0,0],blueCore=[0,0,0];
for(let y=0;y<360;y++)for(let x=0;x<640;x++) {
 const p=(y*640+x)*3;
 if((y<115 || y>245) && Math.max(...red.subarray(p,p+3))>90 && Math.min(...red.subarray(p,p+3))>40) {
  samples++;
  for(let c=0;c<3;c++)starDelta+=Math.abs(red[p+c]-blue[p+c]);
 }
 if(x>=270 && x<370 && y>=145 && y<215)
  for(let c=0;c<3;c++) {redCore[c]+=red[p+c];blueCore[c]+=blue[p+c]}
}
assert.ok(samples>20,'no bright outer-field stars were captured');
assert.ok(starDelta/(samples*3)<3,'star colors changed with the palette');
assert.ok(redCore[0]>redCore[2]*1.4 && blueCore[2]>blueCore[0]*1.4,'the diffuse core stopped following the palette');
console.log(`PASS: ${samples} bright star pixels retain color while the core changes palette; captures: ${dir}`);
