#!/usr/bin/env python3
"""Bounded production-Canvas captures for the particle/radial catalog.

python tests/catalog-visual.py renderer/build/omaviz-render-probe /tmp/catalog
Requires a working Qt OpenGL backend. Never installs or changes user settings.
"""
import os
from pathlib import Path
import re
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
probe = Path(sys.argv[1]).resolve()
out = Path(sys.argv[2]).resolve()
out.mkdir(parents=True, exist_ok=True)
env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='basic',
           QT_QUICK_BACKEND='rhi', QSG_RHI_BACKEND='opengl', QSG_RENDER_LOOP='basic',
           OMAVIZ_PROBE_FIXED_SIZE='1', OMAVIZ_PROBE_TIMESTAMPS='0', OMAVIZ_PROBE_SEQUENCE='1')
def metric(*args):
    return float(subprocess.check_output(['magick',*map(str,args),'-alpha','off','info:'],text=True))

for mode in ('Orbit', 'PixelWave', 'Bokeh', 'Tunnel', 'SolidTunnel', 'Cosmos'):
    for case in ('desktop', 'mini', 'artwork', 'mono', 'silence', 'resize', 'audio', 'reference', 'mono-light', 'custom', 'quiet', 'occlusion'):
        if case == 'occlusion' and mode not in ('SolidTunnel','Cosmos'):
            continue
        if len(sys.argv)>3 and f'{mode}:{case}' not in sys.argv[3:]:
            continue
        width, height = (160,32) if case == 'mini' else (590,540) if case == 'reference' else (640,360)
        background = '#ff00ff' if case == 'occlusion' else '#3d3435' if case == 'reference' else 'white' if case == 'mono-light' else 'black'
        options = 'originalColors:true; '
        if case in ('mono','mono-light'): options += 'mono:true;'
        if case == 'mono-light': options += 'monoLight:true;'
        if case == 'custom': options = 'barColorCustom:true; barColorFrom:"#16b5d4"; barColorMiddleEnabled:true; barColorMiddle:"#8b3bce"; barColorTo:"#faaa75";'
        if case == 'artwork':
            options = 'artworkColors:true; artworkPalette:["#00d5df","#8533ff","#ff3579"];'
        timer = ''
        if case == 'silence':
            timer = 'Timer { interval:400; running:true; onTriggered: { canvas.bands=Array(128).fill(0); canvas.silent=true } }'
        if case == 'resize':
            timer = 'Timer { interval:900; running:true; onTriggered: { canvas.width=180; canvas.height=32 } } Timer { interval:1600; running:true; onTriggered: { canvas.width=600; canvas.height=320 } }'
        source = f'''import QtQuick
import "file:{root}" as App
Rectangle {{
 width:{width}; height:{height}; color:"{background}"
 property int frame: canvas._awake ? 1 : 0
 property var inputBands: []
 property var inputWave: []
 property real inputWaveRms: -1
 property bool inputSilent: true
 property string inputBandLayout: ""
 App.VisualCanvas {{
  id:canvas; width:parent.width; height:parent.height; wave:parent.inputWave; waveRms:parent.inputWaveRms; visual:"{mode}"; silent:false
  themeBottom:"#b9c7e9"; themeTop:"#fff4e1"; {options}
  bands:Array.from({{length:128}},(_,i)=>.04+.3*Math.pow(.5+.5*Math.sin(i*.29),3))
 }}
 {timer}
}}'''
        case_env = dict(env)
        if case in ('audio', 'quiet'):
            source = source.replace('bands:Array.from({length:128},(_,i)=>.04+.3*Math.pow(.5+.5*Math.sin(i*.29),3))',
                                    'bands:parent.inputBands; silent:parent.inputSilent')
            # Remove the original silent binding before setting the live one.
            source = source.replace(f'visual:"{mode}"; silent:false',f'visual:"{mode}"')
            case_env['OMAVIZ_PROBE_ENGINE'] = str(root/'bin/omaviz-engine')
            case_env['OMAVIZ_PROBE_SOURCE'] = 'gen=mixed:amp=0.02' if case == 'quiet' else 'gen=mixed'
        qml = out / f'{mode}-{case}.qml'
        png = out / f'{mode}-{case}.png'
        qml.write_text(source)
        result = subprocess.run(['timeout','-k','2','10',str(probe),str(qml),str(png),'3'],
                                env=case_env, capture_output=True, text=True, timeout=13)
        log = result.stdout + result.stderr
        (out / f'{mode}-{case}.log').write_text(log)
        assert result.returncode == 0, log
        assert not re.search(r'ReferenceError|TypeError|Error:|Failed to',log),log
        if case == 'silence':
            assert 'scene_frame 0' in log, ('silence did not sleep',log)
        peak = metric(png,'-format','%[fx:maxima]')*255
        if case == 'silence':
            assert peak < 3, (mode, 'stale geometry',peak)
        elif case == 'mono-light':
            assert metric(png,'-format','%[fx:minima]')*255<235,(mode,'invisible black mono')
        else:
            assert peak > 20, (mode,case,'empty capture')
        if case in ('desktop','audio','reference','quiet'):
            delta=metric(out/f'{mode}-{case}-1.png',out/f'{mode}-{case}-3.png',
                         '-compose','difference','-composite','-format','%[fx:mean]')
            assert delta>(.00002 if case=='quiet' else .00013),(mode,'motion frozen')
        if case in ('mono','mono-light'):
            assert metric(png,'-fx','max(abs(r-g),abs(r-b))','-format','%[fx:maxima]')==0
        if case == 'occlusion':
            assert metric(png,'-fx','r>0.95&&g<0.05&&b>0.95','-format','%[fx:mean]')==0, 'outside background leaked through solid walls'
        print(f'{mode} {case}: PASS',flush=True)
print(f'Native catalog captures: {out}')
