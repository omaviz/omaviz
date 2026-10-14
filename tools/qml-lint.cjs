'use strict';
const fs = require('node:fs');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
function findQt6Lint() {
  for (const binary of [process.env.QMLLINT6,'/usr/lib/qt6/bin/qmllint','/usr/lib64/qt6/bin/qmllint','qmllint6','qmllint'].filter(Boolean)) {
    const result=spawnSync(binary,['--version'],{encoding:'utf8'});
    if (result.error && result.error.code !== 'ENOENT') throw result.error;
    if (result.status===0 && /qmllint 6\./.test(result.stdout+result.stderr)) return binary;
  }
  return null;
}
function lint(binary) {
  const root=path.resolve(__dirname,'..');
  const files=fs.readdirSync(root).filter(f=>f.endsWith('.qml')).map(f=>path.join(root,f));
  return spawnSync(binary,['--ignore-settings','--duplicate-property-binding','error',...files],{encoding:'utf8'});
}
module.exports={findQt6Lint,lint};
if(require.main===module) {
  const binary=findQt6Lint();
  if(!binary) throw new Error('Qt 6 qmllint is required (set QMLLINT6 if outside standard paths)');
  const result=lint(binary);
  if(result.error) throw result.error;
  if(result.status!==0) { process.stderr.write(result.stdout+result.stderr); process.exit(result.status||1); }
  console.log('PASS: Qt 6 QML syntax. Shell/native type resolution and behavior are checked by the component/native harnesses.');
}
