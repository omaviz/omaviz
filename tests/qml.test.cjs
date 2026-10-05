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
  assert.ok(src.includes('cv.visual === "Strings" ? cv.bands : cv._barArr'),
    "spectrum uses release envelopes while Strings receives distinct frequency drives")
  assert.ok(!/silent \? 0/.test(src), "silent must not hard-zero bars")
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
  // The marker is now derived from what was actually installed (each path is
  // claimed only when the installed file is byte-identical to $SRC), so the
  // copy path and the marker cannot disagree. The old hand-maintained text
  // list had to be kept in sync manually — and silently wasn't.
  assert.ok(/cmp -s "[^"]*PLUGIN_DIR[^"]*" "[^"]*SRC/.test(s),
    "marker must be generated from the installed files, not a hand-written list")
})

// qmllint reports duplicate property names as a WARNING-free parse, but the
// QML engine rejects the whole component ("Type X unavailable"), which
// silently kills the widget. This guard caught exactly that.
test("no QML component declares the same property twice in one scope", () => {
  const pat = /^\s*(?:(?:readonly|required)\s+)?property\s+[A-Za-z_][\w.]*\s+([A-Za-z_]\w*)/
  for (const f of QML) {
    const scopes = [new Map()]
    // Adjacent inline components are separate scopes even at the same indent.
    const source = read(f).replace(/\/\*[^]*?\*\//g, "")
    source.split("\n").forEach((line, i) => {
      const clean = line.replace(/"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|\/\/.*$/g, "")
      const m = pat.exec(clean)
      if (m) {
        const seen = scopes[scopes.length - 1]
        assert.ok(!seen.has(m[1]), `${f}: duplicate property "${m[1]}" (line ${i + 1})`)
        seen.set(m[1], i + 1)
      }
      for (const token of clean) {
        if (token === "{") scopes.push(new Map())
        else if (token === "}" && scopes.length > 1) scopes.pop()
      }
    })
  }
})

// REGRESSION: the bar body was filled with a gradient built from fireColorAt()
// in EVERY mode. The fire ramp's base is hardcoded deep red, which is why the
// base bar colour was always red regardless of theme or custom colours.
test("GPU palette keeps theme/custom colors separate from flame colors", () => {
  const src = read("VisualCanvas.qml")
  assert.ok(src.includes("cv.artReady ? cv.artworkPalette[0] : cv.customMode ? cv.barColorFrom : cv.themeBottom"))
  assert.ok(src.includes("fireBottom: cv.fireColorFrom, fireTop: cv.fireColorTo"))
  const geometry = read("renderer/geometry.cpp")
  assert.ok(geometry.includes("if(!fire) return mix(bottom,top,t)"))
})

// REGRESSION: Panel.vizEnabled read Store.sharedConfig (a non-observable JS
// object property), so the ON/OFF switch never reflected the real config.
test("panel ON/OFF is bound to the reactive config, not to sharedConfig", () => {
  const src = read("Panel.qml")
  assert.ok(!src.includes("getSharedConfig()"), "must not bind to the shadow sharedConfig")
  assert.match(src, /readonly property bool vizEnabled: root\.hcfg \? \(root\.hcfg\.enabled !== false\) : true/)
  // and it must not be assigned imperatively (that would break the binding)
  const setter = src.slice(src.indexOf("function setVizEnabled"), src.indexOf("// ---- Size-freeze"))
  assert.ok(!/^\s*vizEnabled = /m.test(setter), "setVizEnabled must not assign vizEnabled")
})

test("BarWidget routes every config load through syncFromConfig", () => {
  const src = read("BarWidget.qml")
  assert.ok(src.includes("function syncFromConfig(txt)"))
  // exactly ONE place assigns root.config (inside syncFromConfig)
  assert.equal((src.match(/root\.config = Store\.loadFromTOML\(/g) || []).length, 1)
  for (const call of ["root._configReady = true; root.syncFromConfig", "onFileChanged: root.syncFromConfig"]) {
    assert.ok(src.includes(call), `missing ${call}`)
  }
})


test("desktop treats external media metadata as plain text", () => {
  const blocks = read("Desktop.qml").match(/Text\s*\{[^{}]*\}/g) || []
  for (const field of ["playerSource", "trackTitle", "trackArtist"]) {
    const block = blocks.find(s => s.includes(`text: win.${field}`))
    assert.ok(block && block.includes("textFormat: Text.PlainText"), `${field} must not interpret markup`)
  }
})
