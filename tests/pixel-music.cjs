'use strict';
// GPU behavior: held uniform input stays flat; frequency changes reshape it.
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const assert=require('node:assert/strict');
const {spawnSync}=require('node:child_process');
const root=path.resolve(__dirname,'..');
const runtime=process.env.OMAVIZ_RENDER_ROOT || root;
const probe=process.argv[2] || path.join(root,'renderer/build/omaviz-render-probe');
const dir=fs.mkdtempSync(path.join(os.tmpdir(),'omaviz-pixel-music-'));
function run(command,args,options={}) {
 const result=spawnSync(command,args,{timeout:12000,...options});
 assert.ifError(result.error);
 assert.equal(result.status,0,String(result.stdout)+String(result.stderr));
 return result.stdout;
}
for(const [name,bands] of [
 ['uniform','Array(128).fill(.25)'],
 ['bass','Array.from({length:128},(_,i)=>Math.abs(i-20)<8?.7:.005)'],
 ['treble','Array.from({length:128},(_,i)=>Math.abs(i-90)<8?.7:.005)']
]) {
 const qml=path.join(dir,name+'.qml');
 fs.writeFileSync(qml,`import QtQuick
import ${JSON.stringify('file:'+runtime)} as App
Rectangle { width:640; height:360; color:"black"
 App.VisualCanvas { anchors.fill:parent; visual:"PixelWave"; originalColors:true; silent:false; bands:${bands} }
}`);
 run('timeout',['-k','2','8',probe,qml,path.join(dir,name+'.png'),'3'],{
  env:{...process.env,QT_QPA_PLATFORM:'offscreen',QT_QPA_PLATFORMTHEME:'basic',
   QT_QUICK_BACKEND:'rhi',QSG_RHI_BACKEND:'opengl',QSG_RENDER_LOOP:'basic',
   OMAVIZ_PROBE_FIXED_SIZE:'1',OMAVIZ_PROBE_TIMESTAMPS:'0'}
 });
}
const pixels=run('magick',[path.join(dir,'uniform.png'),'-colorspace','gray','-depth','8','gray:-']);
let bottom=-1;
for(let i=0;i<pixels.length;i++) if(pixels[i]>70) bottom=Math.floor(i/640);
assert.ok(bottom>=0,'uniform input was never rendered');
const front=new Set();
for(let i=Math.max(0,bottom-7)*640;i<pixels.length;i++) if(pixels[i]>70) front.add(i%640);
assert.ok(front.size>300,'held uniform input developed an autonomous wave instead of a flat front');
const difference=Number(run('magick',[path.join(dir,'bass.png'),path.join(dir,'treble.png'),
 '-compose','difference','-composite','-format','%[fx:mean]','info:']));
assert.ok(difference>.008,'equal-energy frequency changes did not reshape Pixel Wave');
console.log('PASS: Pixel Wave has no autonomous wave with held input and responds to equal-energy spectrum changes; captures: '+dir);
