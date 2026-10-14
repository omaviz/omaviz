"use strict";
// Native scene-graph verification. Every surface is bounded; user settings are untouched.
const {spawnSync} = require("node:child_process");
const path = require("node:path");
const root = path.resolve(__dirname, "../..");
function run(command, args, env = process.env) {
  const result = spawnSync(command, args, {cwd: root, env, stdio: "inherit", timeout: 120000});
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status || 1);
}
run("cmake", ["-S", "renderer", "-B", "renderer/build", "-DOMAVIZ_RENDER_PROBE=ON", "-DCMAKE_BUILD_TYPE=Release"]);
run("cmake", ["--build", "renderer/build", "--parallel", "2"]);
run("bash", ["tests/renderer-visual.sh", path.join(root, "renderer/build/omaviz-render-probe")], {
  ...process.env, QT_QPA_PLATFORM: "offscreen", QT_QPA_PLATFORMTHEME: "basic",
  QT_QUICK_BACKEND: "rhi", QSG_RHI_BACKEND: "opengl",
});
