'use strict';
const {spawnSync} = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {pathToFileURL} = require('node:url');
const dir = fs.mkdtempSync(path.join(os.tmpdir(),'omaviz-window-'));
try {
  fs.mkdirSync(path.join(dir,'omaviz'));
  // Pause rendering/capture; exercise the real desktop Window in software.
  fs.writeFileSync(path.join(dir,'omaviz/config.toml'),'[desktop]\nenabled = false\n');
  const app = pathToFileURL(path.resolve(__dirname,'..')).href;
  const shell = path.join(dir,'shell.qml');
  fs.writeFileSync(shell, `import QtQuick
import Quickshell
import ${JSON.stringify(app)} as App
ShellRoot {
 id: test
 property int stage: 0
 property int ticks: 0
 App.Desktop { id: desktop }
 function fail(message) { console.error("WINDOW_FAILED " + message); Qt.quit() }
 Timer {
  interval: 100; running: true; repeat: true
  onTriggered: {
   if (++test.ticks > 60) { test.fail("deadline " + test.stage); return }
   if (test.stage === 0) {
    if (Quickshell.env("OMAVIZ_WINDOW_PHASE") === "restore") {
     if (desktop.width !== 520 || desktop.height !== 260) { test.fail("dimensions not restored"); return }
    }
    desktop.toggleFullscreen(); test.stage=1
   } else if (test.stage === 1) {
    if (desktop.visibility !== Window.FullScreen) { test.fail("fullscreen"); return }
    desktop.handleEscape(); test.stage=2
   } else if (test.stage === 2) {
    if (desktop.visibility !== Window.Windowed || desktop._closing) { test.fail("Escape should leave fullscreen"); return }
    desktop.width=520; desktop.height=260; test.stage=3; test.ticks=0
   } else if (test.stage === 3 && test.ticks > 8) {
    desktop.handleEscape()
    if (!desktop._closing) { test.fail("Escape should close windowed desktop"); return }
    console.log("WINDOW_PASS"); test.stage=4
   }
  }
 }
}`);
  for (const phase of ['write','restore']) {
    const result = spawnSync('timeout',['10','quickshell','-p',shell],{
      encoding:'utf8',timeout:12000,
      env:{...process.env,XDG_CONFIG_HOME:dir,OMAVIZ_WINDOW_PHASE:phase,
        QT_QPA_PLATFORM:'offscreen',QT_QPA_PLATFORMTHEME:'',QT_QUICK_BACKEND:'software'}
    });
    const output = result.stdout + result.stderr;
    if (result.error || result.status !== 0 || !output.includes('WINDOW_PASS') || /WINDOW_FAILED|ReferenceError|TypeError/.test(output))
      throw new Error(result.error?.message || output);
  }
  console.log('PASS: real desktop fullscreen, Escape semantics, close, and persisted window dimensions across launches');
} finally { fs.rmSync(dir,{recursive:true,force:true}); }
