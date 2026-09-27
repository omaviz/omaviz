// QML architecture + syntax guards — run: node --test tests/qml.test.cjs
//
// Two layers:
//   1. SYNTAX — every shipped QML/JS file must pass the real Qt validator
//      (qmllint). This is the guard that would have caught the object-literal
//      comma bug that silently killed the plugin.
//   2. ARCHITECTURE — the invariants that make the physics identical on every
//      surface and keep the store a single source of truth.
"use strict"
const fs = require("fs")
const path = require("path")
const { test } = require("node:test")
const assert = require("node:assert/strict")
const { execFileSync } = require("node:child_process")

const ROOT = path.join(__dirname, "..")
const read = (f) => fs.readFileSync(path.join(ROOT, f), "utf8")
const QML = ["VisualCanvas.qml", "Panel.qml", "Desktop.qml", "BarWidget.qml"]
const ALL = [...QML, "Physics.js", "ModelStore.js"]

function haveQmllint() {
  try { execFileSync("qmllint", ["--version"], { stdio: "ignore" }); return true }
  catch { return false }
}
const HAS_QMLLINT = haveQmllint()

for (const f of ALL) {
  test(`qmllint: ${f} has no syntax errors`, { skip: !HAS_QMLLINT && "qmllint not installed" }, () => {
    let out = ""
    try {
      out = execFileSync("qmllint", [path.join(ROOT, f)], { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] })
    } catch (e) {
      out = String(e.stdout || "") + String(e.stderr || "")
    }
    const bad = out.split("\n").filter((l) => /syntax error|expected token|unexpected token|expected `?\}/i.test(l))
    assert.equal(bad.length, 0, `${f} failed to parse:\n${bad.join("\n")}`)
  })
}

test("store-consuming surfaces import ModelStore.js; none use the old Model.js", () => {
  // VisualCanvas is a pure renderer: it imports Physics.js and must NOT
  // depend on the store. The UI surfaces do.
  assert.ok(read("VisualCanvas.qml").includes('import "Physics.js" as Physics'))
  for (const f of ["Panel.qml", "Desktop.qml", "BarWidget.qml"]) {
    const s = read(f)
    assert.ok(s.includes('import "ModelStore.js" as Store'), `${f} must import ModelStore.js as Store`)
  }
  for (const f of QML) {
    const s = read(f)
    assert.ok(!/import\s+"Model\.js"/.test(s), `${f} still imports Model.js`)
  }
  // A stale `Model.` alias reference is only a bug in the QML surfaces (the
  // module was imported as `Model` there); ModelStore.js merely documents the
  // rename in comments.
  for (const f of ["Panel.qml", "Desktop.qml", "BarWidget.qml"]) {
    assert.ok(!/\bModel\./.test(read(f)), `${f} still references Model.*`)
  }
  assert.ok(!fs.existsSync(path.join(ROOT, "Model.js")), "Model.js must be gone")
})

test("every surface binds the SAME physics properties (identical fall)", () => {
  for (const f of ["Panel.qml", "Desktop.qml", "BarWidget.qml"]) {
    const s = read(f)
    for (const prop of ["peakSustainMs", "linearFall"]) {
      assert.ok(s.includes(prop), `${f} must bind ${prop}`)
    }
  }
})

test("VisualCanvas renders the release envelope, never the raw frame", () => {
  const src = read("VisualCanvas.qml")
  // Bars must be painted from _barArr (the envelope), not from bands[...].
  assert.ok(src.includes("var v = _barArr[i] || 0"), "bar body must paint from _barArr")
  assert.ok(src.includes("var mv = _barArr[m] || 0"), "reflection must paint from _barArr")
  // And the old silent->0 hard-zero must be gone from the paint paths.
  assert.ok(!/silent \? 0/.test(src), "silent must not hard-zero bars")
  // Physics delegated to the tested module.
  assert.ok(src.includes('import "Physics.js" as Physics'))
  assert.ok(src.includes("Physics.step("))
})

test("VisualCanvas keeps its no-allocation hot path", () => {
  const src = read("VisualCanvas.qml")
  for (const buf of ["_bandBuf", "_bandUp", "_barArr", "_peakArr", "_peakHold", "_targets"]) {
    assert.ok(src.includes(buf), `missing scratch buffer ${buf}`)
  }
})

test("no spawn-time physics flag anywhere (physics is renderer-side)", () => {
  for (const f of [...QML, "install.sh", "build.sh"]) {
    if (!fs.existsSync(path.join(ROOT, f))) continue
    assert.ok(!read(f).includes("--fall-mode"), `${f} still passes --fall-mode`)
  }
})

test("installer ships ModelStore.js + Physics.js and never the old Model.js", () => {
  const s = read("install.sh")
  assert.ok(s.includes("ModelStore.js"), "install.sh must ship ModelStore.js")
  assert.ok(s.includes("Physics.js"), "install.sh must ship Physics.js")
  assert.ok(!/Model\.js/.test(s), "install.sh must not reference Model.js")
  // Both the copy path and the marker must agree.
  assert.equal((s.match(/ModelStore\.js/g) || []).length, 2, "copy + marker must both list ModelStore.js")
  assert.equal((s.match(/Physics\.js/g) || []).length, 2, "copy + marker must both list Physics.js")
})

// qmllint reports duplicate property names as a WARNING-free parse, but the
// QML engine rejects the whole component ("Type X unavailable"), which
// silently kills the widget. This guard caught exactly that.
test("no QML component declares the same property twice in one scope", () => {
  const pat = /^(\s*)property\s+[A-Za-z_][\w.]*\s+([A-Za-z_]\w*)/
  for (const f of QML) {
    const seen = new Map()
    read(f).split("\n").forEach((line, i) => {
      const m = pat.exec(line)
      if (!m) return
      const key = m[1].length + ":" + m[2]      // indent + property name
      if (seen.has(key)) {
        assert.fail(`${f}: duplicate property "${m[2]}" (lines ${seen.get(key)} and ${i + 1})`)
      }
      seen.set(key, i + 1)
    })
  }
})
