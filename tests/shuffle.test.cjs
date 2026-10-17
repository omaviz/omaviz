'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const moduleStore={exports:{}};
new Function('module',fs.readFileSync(require('node:path').join(__dirname,'../ModelStore.js'),'utf8').replace(/^\.pragma library\s*/,''))(moduleStore);
const S=moduleStore.exports;
test('shuffle overlays mode-specific looks, avoids immediate repeats, and restores the exact saved settings',()=>{
 let text=S.toTOML({...S.defaultConfig(),visual:'Siri',siriClassic:true,sensitivity:1.35,colorMode:'Custom',barColorFrom:'#123456'});
 text=S.patchSettings(text,'selection',{waveforms:'Siri'});
 text=S.patchSettings(text,'looks.Bokeh',{color_mode:'Original'});
 const before=S.readConfigFromText(text),savedSections=text.slice(text.indexOf('[selection]'));
 text=S.setShuffle(text,true);
 const seen=new Set();let seed=22;
 const rng=()=>{seed=(1664525*seed+1013904223)>>>0;return seed/4294967296};
 for(let i=0;i<160;i++) {
  const previous=S.readConfigFromText(text).visual,look=S.randomLook(text,rng);
  assert.notEqual(look.visual,previous);seen.add(look.visual);
  text=S.patchSettings(text,'shuffle',{look:JSON.stringify(look)});
  const cfg=S.readConfigFromText(text);
  assert.equal(cfg.visual,look.visual);assert.equal(cfg.sensitivity,1.35);
  assert.equal(S.readTomlValue(text,'desktop','visual'),'Siri');
  assert.equal(text.slice(text.indexOf('[selection]'),text.indexOf('[shuffle]')).trim(),savedSections.trim());
  if(cfg.visual==='Bars' && cfg.geometry==='Spikes') assert.equal(cfg.colorMode,'Flame');
  if(cfg.visual!=='Bars') assert.notEqual(cfg.colorMode,'Flame');
 }
 assert.equal(seen.size,10);
 text=S.setShuffle(text,false);
 assert.deepEqual(S.readConfigFromText(text),before);
});
test('corrupt shuffle state falls back to the saved selection and cannot alter audio or enable state',()=>{
 let text=S.setShuffle(S.toTOML(S.defaultConfig()),true);
 text=S.patchSettings(text,'shuffle',{look:'invalid json'});
 assert.equal(S.readConfigFromText(text).visual,'Bars');
 text=S.patchSettings(text,'shuffle',{look:JSON.stringify({visual:'Cosmos',enabled:false,sensitivity:99,geometry:'invalid'})});
 const cfg=S.readConfigFromText(text);
 assert.equal(cfg.visual,'Cosmos');assert.equal(cfg.enabled,true);assert.equal(cfg.sensitivity,1);assert.equal(cfg.geometry,'Bars');
});
