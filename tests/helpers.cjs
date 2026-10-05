'use strict';
const fs = require('node:fs');
const path = require('node:path');
exports.load = name => {
  const source = fs.readFileSync(path.join(__dirname, '..', name), 'utf8').replace(/^\.pragma library\s*/, '');
  const module = {exports: {}};
  new Function('module', 'exports', source)(module, module.exports);
  return module.exports;
};
