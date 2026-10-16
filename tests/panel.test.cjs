"use strict";
const {test} = require('node:test');
const assert = require('node:assert/strict');
const Store = require('./helpers.cjs').load('ModelStore.js');

test('switching families restores the previous visual and its complete look', () => {
 let text=Store.toTOML(Store.defaultConfig());
 text=Store.patchSettings(text,'desktop',{geometry:'Stacks',color_mode:'Flame',peak_falloff:0.8});
 text=Store.patchSettings(text,'audio',{sensitivity:2.2});
 text=Store.selectVisual(text,'Strings');
 assert.equal(Store.readConfigFromText(text).fire,false);
 text=Store.patchSettings(text,'desktop',{color_mode:'Custom',bar_color_from:'#123456',scope_thickness:4});
 text=Store.selectGroup(text,'spectrum');
 let cfg=Store.readConfigFromText(text);
 assert.equal(cfg.visual,'Bars'); assert.equal(cfg.geometry,'Stacks'); assert.equal(cfg.colorMode,'Flame'); assert.equal(cfg.sensitivity,2.2);
 text=Store.selectGroup(text,'waveforms'); cfg=Store.readConfigFromText(text);
 assert.equal(cfg.visual,'Strings'); assert.equal(cfg.barColorFrom,'#123456'); assert.equal(cfg.scopeThickness,4); assert.equal(cfg.colorMode,'Custom');
});
test('edits persist automatically through reload and repeated visualization switches', () => {
 let text=Store.toTOML(Store.defaultConfig());
 for (const [mode, geometry, color, mono] of [['Bars','Stacks','Flame',true],['Siri','Bars','Custom',false],['Strings','Spikes','Artwork',true]]) {
   text=Store.selectVisual(text,mode);
   text=Store.patchSettings(text,'desktop',{geometry,color_mode:color,mono,siri_classic:true,siri_travel:true,reflect:false});
   assert.equal(Store.readTomlValue(text,'looks.'+mode,'geometry'),geometry);
 }
 // Rehydrate the serialized document as reopening the app does.
 text=String(text);
 for (let round=0;round<3;round++) for (const [mode, geometry, color, mono] of [['Bars','Stacks','Flame',true],['Siri','Bars','Custom',false],['Strings','Spikes','Artwork',true]]) {
   text=Store.selectVisual(text,mode);
   const cfg=Store.readConfigFromText(text);
   assert.equal(cfg.geometry,geometry); assert.equal(cfg.colorMode,color); assert.equal(cfg.mono,mono);
   assert.equal(cfg.siriClassic,true); assert.equal(cfg.siriTravel,true); assert.equal(cfg.reflect,false);
 }
});
test('geometry buttons replace the previous choice and retain it across categories', () => {
 let text='# keep me\n[desktop]\nfire = true\nstacks = true\n[custom]\nuntouched = 42\n';
 for (const [spikes,stacks,expected] of [[false,false,'Bars'],[false,true,'Stacks'],[true,false,'Spikes']]) {
   text=Store.patchSettings(text,'desktop',{spikes,stacks});
   text=Store.selectGroup(text,'waveforms'); text=Store.selectGroup(text,'spectrum');
   const cfg=Store.readConfigFromText(text);
   assert.equal(cfg.geometry,expected); assert.equal(cfg.spikes,spikes); assert.equal(cfg.stacks,stacks);
 }
 assert.ok(text.includes('# keep me')); assert.equal(Store.readTomlValue(text,'custom','untouched'),'42');
 assert.equal(Store.selectVisual(text,'invalid'),text);
});

test('particle and radial categories remember independent palettes and response', () => {
 let text=Store.toTOML(Store.defaultConfig());
 for (const [mode,color,response] of [['Orbit','Custom',.4],['PixelWave','Artwork',2.1],['Bokeh','Theme',1.5]]) {
   text=Store.selectVisual(text,mode);
   text=Store.patchSettings(text,'desktop',{color_mode:color,bar_color_from:'#123abc'});
   text=Store.patchSettings(text,'audio',{sensitivity:response});
 }
 for (const [mode,color,response] of [['Orbit','Custom',.4],['PixelWave','Artwork',2.1],['Bokeh','Theme',1.5]]) {
   text=Store.selectVisual(text,mode);
   const cfg=Store.readConfigFromText(text);
   assert.equal(cfg.visual,mode); assert.equal(cfg.colorMode,color); assert.equal(cfg.sensitivity,response);
   assert.equal(cfg.barColorFrom,'#123abc'); assert.equal(Store.supportsArtwork(mode),true);
 }
 text=Store.selectGroup(text,'radial'); assert.equal(Store.readConfigFromText(text).visual,'Orbit');
 text=Store.selectGroup(text,'particles'); assert.equal(Store.readConfigFromText(text).visual,'Bokeh');
});

test('new particle and radial looks default to Original and preserve explicit theme choices', () => {
 let text=Store.toTOML(Store.defaultConfig());
 for (const mode of ['Orbit','PixelWave','Bokeh']) {
   text=Store.selectVisual(text,mode);
   assert.equal(Store.readConfigFromText(text).colorMode,'Original');
   text=Store.patchSettings(text,'desktop',{color_mode:'Theme'});
 }
 for (const mode of ['Orbit','PixelWave','Bokeh']) {
   text=Store.selectVisual(text,mode);
   assert.equal(Store.readConfigFromText(text).colorMode,'Theme');
 }
 text=Store.patchSettings(text,'desktop',{color_mode:'Original'});
 text=Store.selectVisual(text,'Bars');text=Store.selectVisual(text,'Bokeh');
 assert.equal(Store.readConfigFromText(text).colorMode,'Original');
 assert.equal(Store.readConfigFromText(Store.toTOML(Store.readConfigFromText(text))).colorMode,'Original');
});

test('production palette handler persists Original explicitly through the settings funnel', () => {
 const fs=require('node:fs');
 const source=fs.readFileSync(require('node:path').join(__dirname,'../BarWidget.qml'),'utf8');
 const method=source.match(/  function setColorMode\(mode\) \{[\s\S]*?\n  \}/)[0];
 let text=Store.selectVisual(Store.toTOML(Store.defaultConfig()),'Bokeh');
 const select=Function('root',method+'; return setColorMode')({
   writeVizMap: values => { text=Store.patchSettings(text,'desktop',values); }
 });
 for(const mode of ['Original','Theme','Custom','Artwork','Original']) {
   assert.equal(select(mode),true);
   assert.equal(Store.readConfigFromText(text).colorMode,mode);
 }
 assert.equal(select('unknown'),false);
});
