#!/usr/bin/env python3
"""Deterministic native comparisons; requires the bounded render probe + ImageMagick.

Usage: python3 tests/renderer-compare.py /path/to/omaviz-render-probe output-dir [Siri|Strings|Bars]
Does not install, restart the shell, or alter user configuration.
"""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parent.parent
mode = sys.argv[3] if len(sys.argv) > 3 else "Siri"
assert mode in ("Siri", "Strings", "Bars")
legacy_key = "OMAVIZ_" + mode.upper() + "_LEGACY"
probe = Path(sys.argv[1]).resolve()
output = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(tempfile.mkdtemp(prefix="omaviz-siri-"))
output.mkdir(parents=True, exist_ok=True)
scene = (root / "tests/renderer-scene.qml").read_text().replace('"../native"', '"file:' + str(root / "native") + '"')
scene = scene.replace('mode:"Siri"', f'mode:"{mode}"')
cases = {
    "desktop": {},
    "mini": {"width: 754; height: 405": "width: 160; height: 32"},
    "large-custom": {"width: 754; height: 405": "width: 1200; height: 500", "bool custom: false": "bool custom: true"},
    "white": {"bool mono: false": "bool mono: true"},
    "black": {"bool mono: false": "bool mono: true", "bool monoLight: false": "bool monoLight: true", 'color: "black"': 'color: "white"'},
    "quiet": {"amplitude: .07": "amplitude: .002", "phaseOffset: 0": "phaseOffset: 2.3"},
    "silence": {"amplitude: .07": "amplitude: 0"},
    "loud": {"amplitude: .07": "amplitude: 1", "phaseOffset: 0": "phaseOffset: 6.8"},
    "attack": {"frame<90": "frame<45", "property int frame: 0": "property int frame: 0\n    onFrameChanged: if(frame===30) amplitude=.3"},
    "release": {"property int frame: 0": "property int frame: 0\n    onFrameChanged: if(frame===60) amplitude=0"},
    "style-resize": {"property int frame: 0": "property int frame: 0\n    onFrameChanged: if(frame===45) { custom=true; gain=2; mesh.width=400; mesh.height=133 }"},
}
if mode == "Siri":
    scene = scene.replace('mode:"Siri",', 'mode:"Siri", siriClassic:true,')
    for name, levels in {"bass":[.05,0,0,0,0,0], "treble":[0,0,0,0,0,.05], "mixed":[.01,.03,.008,.006,.04,.001]}.items():
        cases[name] = {'mode:"Siri",':'mode:"Siri", compactSiri:true,',
                       "inputBands: [.1,.5,.8,.3,.2,.7,.9,.4]":"inputBands: " + json.dumps(levels)}
    cases["classic-roundtrip"] = {"property int frame: 0": "property int frame: 0\n    onFrameChanged: if(frame===30 || frame===60) mesh.style=Object.assign({},mesh.style,{siriClassic:frame===60})"}
    cases["travel"] = {'mode:"Siri",': 'mode:"Siri", siriTravel:true,'}
    cases["travel-mini"] = {'mode:"Siri",': 'mode:"Siri", siriTravel:true,', "width: 754; height: 405": "width: 160; height: 32"}
    cases["travel-toggle"] = {"property int frame: 0": "property int frame: 0\n    onFrameChanged: if(frame===45) mesh.style = Object.assign({},mesh.style,{siriTravel:true})"}
if mode == "Strings":
    cases["silence"]["inputBands: [.1,.5,.8,.3,.2,.7,.9,.4]"] = "inputBands: []"
    cases["thick"] = {"lineWidth: 2": "lineWidth: 5"}
    cases["thin"] = {"lineWidth: 2": "lineWidth: 1"}
if mode == "Bars":
    scene = scene.replace("Math.min(parent.height - 8, width/3)", "parent.height - 8")
    scene = scene.replace("mesh.submit(bands,[],inputWave", "mesh.submit(bands,[.12,.55,.9,.4,.02,.01,1,.6],inputWave")
    scene = scene.replace('mode:"Bars",', 'mode:"Bars", peaks:true, gap:1, reflect:false, stacks:false, spikes:false, wash:false, horizontal:false, stackScale:1,')
    cases = {key: cases[key] for key in ("desktop", "mini", "large-custom", "white", "black", "style-resize")}
    cases.update({
        "reflection": {"reflect:false": "reflect:true"},
        "stacks": {"stacks:false": "stacks:true"},
        "stack-scale": {"stacks:false": "stacks:true", "stackScale:1": "stackScale:2.3"},
        "spikes": {"spikes:false": "spikes:true"},
        "fire": {'peaks:true': 'peaks:true, fire:true'},
        "horizontal": {"horizontal:false": "horizontal:true"},
        "horizontal-fire": {"horizontal:false": "horizontal:true", 'peaks:true': 'peaks:true, fire:true'},
        "wash": {"wash:false": "wash:true"},
        "combined": {"wash:false": "wash:true", "reflect:false": "reflect:true", "stacks:false": "stacks:true", 'peaks:true': 'peaks:true, fire:true'},
        "silence": {"inputBands: [.1,.5,.8,.3,.2,.7,.9,.4]": "inputBands: [0,0,0,0,0,0,0,0]"},
        "alpha": {'bottom:"#008c95"': 'bottom:"#55008c95"', 'middle:"#663cc8"': 'middle:"#99663cc8"', 'top:"#c5c94b"': 'top:"#aac5c94b"', "wash:false": "wash:true", "reflect:false": "reflect:true"},
        "fallback": {"inputBands: [.1,.5,.8,.3,.2,.7,.9,.4]": "inputBands: Array.from({length:1025}, (_,i)=>(i%17)/16)"},
        "count-change": {"property int frame: 0": "property int frame: 0\n    onFrameChanged: if(frame===45) inputBands=[1,.01,.51]"},
        "dense": {"inputBands: [.1,.5,.8,.3,.2,.7,.9,.4]": "inputBands: Array.from({length:256}, (_,i)=>(i%17)/16)"},
    })
if len(sys.argv) > 4:
    selected = set(sys.argv[4:])
    assert selected <= cases.keys(), "unknown comparison case"
    cases = {name: value for name, value in cases.items() if name in selected}
results = []
for name, replacements in cases.items():
    text = scene
    for old, new in replacements.items():
        assert old in text, old
        text = text.replace(old, new)
    source = output / (name + ".qml")
    source.write_text(text)
    for backend in ("legacy", "shader"):
        # Compare full-band legacy input against compact strand drives too.
        source.write_text(text.replace("compactStrings: false", "compactStrings: true")
                          if mode == "Strings" and backend == "shader" else text)
        # Visual equality does not need a render thread. The basic loop avoids
        # Wayland render-thread shutdown races between short-lived probes.
        env = dict(os.environ, QSG_RENDER_LOOP="basic", OMAVIZ_PROFILE="1", OMAVIZ_PROBE_FIXED_SIZE="1", OMAVIZ_PROBE_TIMESTAMPS="0")
        if mode == "Bars":
            env["OMAVIZ_SPECTRUM_RETAINED"] = "1"
        env.pop(legacy_key, None)
        if backend == "legacy":
            env[legacy_key] = "1"
        with (output / f"{name}-{backend}.log").open("w") as log:
            subprocess.run(["timeout", "-k", "2", "12", str(probe), str(source), str(output / f"{name}-{backend}.png"), "3"],
                           env=env, stdout=log, stderr=log, check=True, timeout=15)
        log = (output / f"{name}-{backend}.log").read_text()
        assert not re.search(r"ReferenceError|TypeError|Shader.*failed|Failed to.*shader", log), log
        assert f"scene_frame {45 if name == 'attack' else 90}" in log, "capture before deterministic sequence finished"
    result = subprocess.run(["magick", "compare", "-metric", "RMSE", str(output / f"{name}-legacy.png"),
                             str(output / f"{name}-shader.png"), str(output / f"{name}-diff.png")], capture_output=True, text=True)
    assert result.returncode in (0, 1), result.stderr
    error = float(re.search(r"\(([^)]+)\)", result.stderr)[1])
    # Allow floating-point shader/raster rounding, not altered geometry/design.
    assert error < .001, f"{name}: normalized RMSE {error}"
    results.append({"case": name, "normalized_rmse": error})
    print(f"{name}: PASS ({error:.8f})", flush=True)
(output / "report.json").write_text(json.dumps(results, indent=2) + "\n")
env = dict(os.environ, QSG_RENDER_LOOP="basic", OMAVIZ_PROBE_FIXED_SIZE="1", OMAVIZ_PROBE_TIMESTAMPS="0")
with (output / "wake.log").open("w") as log:
    subprocess.run(["timeout", "-k", "2", "12", str(probe), str(root / "tests/siri-wake.qml"),
                    str(output / "wake.png"), "3"], env=env, stdout=log, stderr=log, check=True, timeout=15)
assert "SIRI_WAKE_PASS" in (output / "wake.log").read_text(), "compact audio wake/settle check failed"
print("compact wake/settle: PASS", flush=True)
print(output)
