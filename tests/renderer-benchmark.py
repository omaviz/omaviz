#!/usr/bin/env python3
"""Matched Linux CPU/DRM measurements, including the Siri-only compact feed.
Set OMAVIZ_BENCH_BASELINE_ROOT + OMAVIZ_BENCH_BASELINE_RETAINED=1 to compare
a prior retained build; OMAVIZ_BENCH_SOURCE selects a shared deterministic input.

Usage: python3 tests/renderer-benchmark.py /path/to/omaviz-render-probe output-dir [Siri|Strings|Bars]
Four automatically closing 8-second runs; samples seconds 2–7 after startup.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

root = Path(__file__).resolve().parent.parent
mode = sys.argv[3] if len(sys.argv) > 3 else "Siri"
assert mode in ("Siri", "Strings", "Bars")
legacy_key = "OMAVIZ_" + mode.upper() + "_LEGACY"
probe = Path(sys.argv[1]).resolve()
output = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(tempfile.mkdtemp(prefix="omaviz-siri-bench-"))
output.mkdir(parents=True, exist_ok=True)
scene = output / "scene.qml"
scene.write_text('''import QtQuick
import "file:ROOT" as O
Rectangle {
    width:754; height:405; color:"black"
    property var inputWave: []
    property int inputWaveSerial: 0
    property var inputBands: []
    property string inputBandLayout: ""
    property bool inputSilent: false
    O.VisualCanvas {
        width:parent.width-8; height:width/3; anchors.centerIn:parent
        visual:"Siri"; siriClassic:true; wave:inputWave; waveSerial:inputWaveSerial; bands:inputBands; bandLayout:inputBandLayout; silent:inputSilent
    }
}
'''.replace("ROOT", str(root)).replace('visual:"Siri"', f'visual:"{mode}"'))
if mode == "Bars":
    scene.write_text(scene.read_text().replace("height:width/3", "height:parent.height-8")
                     .replace('visual:"Bars";', 'visual:"Bars"; barCount:Math.max(16,Math.floor(width/10));'))
if mode == "Bars" and len(sys.argv) > 4:
    variant = sys.argv[4]
    assert variant in ("stacks", "spikes", "combined")
    extra = {"stacks": "stacks:true; stackScale:2;", "spikes": "spikes:true;",
             "combined": "stacks:true; stackScale:2; reflect:true; wash:true; fire:true;"}[variant]
    scene.write_text(scene.read_text().replace('visual:"Bars";', 'visual:"Bars"; ' + extra))
hz = os.sysconf("SC_CLK_TCK")


def child_of(pid):
    return int(Path(f"/proc/{pid}/task/{pid}/children").read_text().split()[0])


def snapshot(pid):
    path = Path("/proc") / str(pid)
    fields = (path / "stat").read_text().split(") ", 1)[1].split()
    clients = {}
    for entry in (path / "fdinfo").glob("*"):
        data = dict(line.split(":", 1) for line in entry.read_text().splitlines() if ":" in line)
        if "drm-client-id" in data:
            key = (data.get("drm-pdev"), data["drm-client-id"])
            clients[key] = int(data.get("drm-engine-gfx", "0").split()[0])
    return {"cpu": (int(fields[11]) + int(fields[12])) / hz,
            "gfx": sum(clients.values()) / 1e9}


scene_text = scene.read_text()
baseline_root = os.environ.get("OMAVIZ_BENCH_BASELINE_ROOT", str(root))
rows = []
for trial, backend in enumerate(("legacy", "shader", "shader", "legacy")):
    scene.write_text(scene_text.replace('"file:' + str(root) + '"',
                                          '"file:' + (baseline_root if backend == "legacy" else str(root)) + '"'))
    env = dict(os.environ, OMAVIZ_PROFILE="1", OMAVIZ_PROBE_FIXED_SIZE="1",
               OMAVIZ_PROBE_ENGINE=str(root / "bin/omaviz-engine"),
               OMAVIZ_PROBE_SOURCE=os.environ.get("OMAVIZ_BENCH_SOURCE", "gen=tone"), OMAVIZ_PROBE_BANDS="256",
               OMAVIZ_PROBE_WAVE="0" if mode == "Bars" else "1", OMAVIZ_PROBE_TIMESTAMPS="1")
    for key in (legacy_key, "OMAVIZ_PROBE_SIRI", "OMAVIZ_PROBE_STRINGS"):
        env.pop(key, None)
    if mode == "Bars":
        env["OMAVIZ_SPECTRUM_RETAINED"] = "1"
    if backend == "legacy" and not os.environ.get("OMAVIZ_BENCH_BASELINE_RETAINED"):
        env[legacy_key] = "1"
    if mode == "Siri":
        env["OMAVIZ_PROBE_SIRI"] = "1"
    elif mode == "Strings" and backend == "shader":
        env["OMAVIZ_PROBE_STRINGS"] = "1"
    with (output / f"{trial}-{backend}.log").open("w") as log:
        process = subprocess.Popen(["timeout", "-k", "2", "12", str(probe), str(scene),
                                    str(output / f"{trial}-{backend}.png"), "8"],
                                   env=env, stdout=log, stderr=log)
        try:
            time.sleep(2)
            renderer_pid = child_of(process.pid)
            engine_pid = child_of(renderer_pid)
            before, engine_before = snapshot(renderer_pid), snapshot(engine_pid)
            start = time.monotonic()
            time.sleep(5)
            after, engine_after = snapshot(renderer_pid), snapshot(engine_pid)
            elapsed = time.monotonic() - start
            assert process.wait(timeout=8) == 0, f"{backend} probe failed"
        finally:
            # timeout also bounds the child if collection fails early.
            if process.poll() is None:
                process.wait(timeout=15)
    cpu = (after["cpu"] - before["cpu"]) / elapsed * 100
    engine_cpu = (engine_after["cpu"] - engine_before["cpu"]) / elapsed * 100
    row = {"backend": backend, "renderer_cpu_pct": round(cpu, 3),
           "engine_cpu_pct": round(engine_cpu, 3), "total_cpu_pct": round(cpu + engine_cpu, 3),
           "gpu_gfx_busy_pct": round((after["gfx"] - before["gfx"]) / elapsed * 100, 3)}
    rows.append(row)
    print(json.dumps(row), flush=True)
(output / "report.json").write_text(json.dumps(rows, indent=2) + "\n")
print(output)
