#!/usr/bin/env python3
"""Matched input/timing probes against an independently saved runtime.

python tests/ambient-benchmark.py PROBE BASELINE_ROOT OUTPUT_DIR
Four alternating trials per mode. This measures submission CPU and offscreen
frame timing, not image parity or universal GPU speedups. Requires ImageMagick
only for the optional capture inspection performed outside this script.
"""
import json
import os
from pathlib import Path
import re
import statistics
import subprocess
import sys

root=Path(__file__).resolve().parents[1]
probe=Path(sys.argv[1]).resolve()
baseline=Path(sys.argv[2]).resolve()
out=Path(sys.argv[3]).resolve();out.mkdir(parents=True,exist_ok=True)
assert baseline!=root and (baseline/'native/libomavizrenderer.so').is_file()
rows=[]
selected=next((arg.split('=',1)[1].split(',') for arg in sys.argv[4:] if arg.startswith('--modes=')),['Orbit','PixelWave','Bokeh'])
assert set(selected)<=set(('Orbit','PixelWave','Bokeh'))
for mode in selected:
    for trial,backend in enumerate(('before','after','after','before')):
        runtime=baseline if backend=='before' else root
        qml=out/f'{mode}-{trial}.qml'
        qml.write_text(f'''import QtQuick
import "file:{runtime}" as O
Rectangle {{
 width:960; height:540; color:"black"
 property int frame:0
 O.VisualCanvas {{
  id:canvas; anchors.fill:parent; visual:"{mode}"; silent:false
  themeBottom:"#b9c7e9";themeTop:"#fff4e1"
 }}
 FrameAnimation {{
  running:true
  onTriggered: {{
   frame++
   canvas.bands=Array.from({{length:128}},(_,i)=>.08+.25*Math.pow(.5+.5*Math.sin(i*.19+frame*.037),2))
   canvas.wave=Array.from({{length:128}},(_,i)=>.12*Math.sin(i*.13+frame*.07))
  }}
 }}
}}''')
        env=dict(os.environ,QT_QPA_PLATFORM='offscreen',QT_QPA_PLATFORMTHEME='basic',
                 QT_QUICK_BACKEND='rhi',QSG_RHI_BACKEND='opengl',QSG_RENDER_LOOP='basic',
                 OMAVIZ_PROFILE='1',OMAVIZ_PROBE_FIXED_SIZE='1',OMAVIZ_PROBE_TIMESTAMPS='1',QSG_INFO='1')
        log_path=out/f'{mode}-{trial}.log'
        if '--reuse' in sys.argv[4:]:
            log=log_path.read_text()
        else:
            run=subprocess.run(['timeout','-k','2','12',str(probe),str(qml),str(out/f'{mode}-{trial}.png'),'6'],
                               env=env,capture_output=True,text=True,timeout=15)
            log=run.stdout+run.stderr;log_path.write_text(log)
            assert run.returncode==0,log
        assert not re.search(r'ReferenceError|TypeError|Error:|Failed to',log),log
        # A pre-audio empty legacy node also logs its zero-frame destruction.
        # Only measure the live node, rather than accidentally selecting zero.
        live=[match for match in re.finditer(r'(?:geometry|ambient \w+) mean_cpu_ms ([\d.]+) frames (\d+)(?: rebuilds (\d+))?',log)
              if int(match[2])>=200]
        assert len(live)==1,log
        cpu=live[0]
        timing=re.search(r'frames (\d+) p50_ms ([\d.]+) p95_ms ([\d.]+)',log)
        process=re.search(r'steady_cpu_pct ([\d.]+)',log)
        gpu=re.search(r'gpu_p95_ms ([-\d.]+)',log)
        assert cpu and timing and process and int(timing[1])>=200,log
        if backend=='after': assert int(cpu[3])==1,('steady animation rebuilt the mesh',log)
        row=dict(mode=mode,trial=trial,backend=backend,submission_ms=float(cpu[1]),
                 frames=int(timing[1]),p95_ms=float(timing[3]),process_cpu_pct=float(process[1]),gpu_p95_ms=float(gpu[1]) if gpu else -1)
        rows.append(row);print(json.dumps(row),flush=True)
summary=[]
for mode in selected:
    row={'mode':mode}
    for backend in ('before','after'):
        samples=[r for r in rows if r['mode']==mode and r['backend']==backend]
        row[backend]={key:statistics.mean(r[key] for r in samples)
                      for key in ('submission_ms','p95_ms','process_cpu_pct','gpu_p95_ms')}
    summary.append(row)
(out/'report.json').write_text(json.dumps({'trials':rows,'summary':summary},indent=2)+'\n')
print(json.dumps(summary,indent=2))
