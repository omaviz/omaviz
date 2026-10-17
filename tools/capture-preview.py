#!/usr/bin/env python3
"""Capture production visualizations from live PipeWire without changing settings.

The native probe owns a separate bounded capture stream and closes every surface.
No synthesized audio or artwork is used. Mini/Settings are actual grim captures
and are recorded separately in the provenance manifest.
"""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SHOTS = ROOT / 'docs/screenshots/marketing'
SCENES = [
    ('Cosmos', 'Cosmos', 1720, 360, 'originalColors:true;'),
    ('Spectrum', 'Bars', 1280, 480, 'peaks:true;reflect:true;'),
    ('Spikes', 'Bars', 1280, 480, 'spikes:true;fire:true;peaks:false;reflect:false;'),
    ('Stacks', 'Bars', 1280, 480, 'stacks:true;peaks:true;reflect:true;stackScale:2;'),
    ('Siri', 'Siri', 960, 320, ''),
    ('ClassicSiri', 'Siri', 960, 320, 'siriClassic:true;'),
    ('Strings', 'Strings', 960, 540, ''),
    ('Waves', 'Waves', 960, 320, ''),
    ('Bokeh', 'Bokeh', 960, 600, 'originalColors:true;'),
    ('PixelWave', 'PixelWave', 960, 600, 'originalColors:true;'),
    ('Orbit', 'Orbit', 960, 600, 'originalColors:true;'),
    ('Spiral', 'Tunnel', 960, 600, 'originalColors:true;'),
    ('Tunnel', 'SolidTunnel', 960, 600, 'originalColors:true;'),
]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--only', nargs='*', choices=[s[0] for s in SCENES])
    parser.add_argument('--seconds', type=int, default=6)
    parser.add_argument('--gain', type=float, default=1.0, help='Production Response setting (0.1–4); recorded with each capture')
    parser.add_argument('--best-frame', action='store_true', help='Choose the brightest genuine frame from a bounded native sequence')
    args = parser.parse_args()
    assert 3 <= args.seconds <= 20
    assert .1 <= args.gain <= 4
    SHOTS.mkdir(parents=True, exist_ok=True)
    provenance = SHOTS / 'captures.json'
    data = json.loads(provenance.read_text()) if provenance.exists() else {'captures': []}
    data['version'] = json.loads((ROOT / 'manifest.json').read_text())['version']
    data['renderer'] = subprocess.check_output(['sha256sum', str(ROOT / 'native/libomavizrenderer.so')], text=True).split()[0]
    with tempfile.TemporaryDirectory(prefix='omaviz-live-preview-') as folder:
        for name, mode, width, height, options in SCENES:
            if args.only and name not in args.only:
                continue
            source = Path(folder) / f'{name}.qml'
            source.write_text(f'''import QtQuick
import "file:{ROOT}" as App
Rectangle {{
 width:{width};height:{height};color:"black"
 property var inputBands:[]
 property var inputWave:[]
 property real inputWaveRms:-1
 property bool inputSilent:true
 property string inputBandLayout:""
 property string inputSource:""
 property int audibleFrames:0
 readonly property int frame:audibleFrames
 onInputBandsChanged: if(!inputSilent) audibleFrames++
 App.VisualCanvas {{
  anchors.fill:parent;visual:"{mode}";bands:parent.inputBands;wave:parent.inputWave
  waveRms:parent.inputWaveRms;silent:parent.inputSilent;bandLayout:parent.inputBandLayout
  sensitivity:{args.gain};barCount:96;themeBottom:"#e68e0d";themeTop:"#f59e0b";{options}
 }}
}}''')
            env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='basic',
                       QT_QUICK_BACKEND='rhi', QSG_RHI_BACKEND='opengl', QSG_RENDER_LOOP='basic',
                       OMAVIZ_PROBE_FIXED_SIZE='1', OMAVIZ_PROBE_TIMESTAMPS='0',
                       OMAVIZ_PROBE_ENGINE=str(ROOT / 'bin/omaviz-engine'), OMAVIZ_PROBE_SOURCE='auto',
                       OMAVIZ_PROBE_BANDS='256')
            if mode == 'Siri':
                env['OMAVIZ_PROBE_SIRI'] = '1'
            if mode == 'Strings':
                env['OMAVIZ_PROBE_STRINGS'] = '1'
            if args.best_frame:
                env['OMAVIZ_PROBE_SEQUENCE'] = '1'
            output = Path(folder) / f'{name}.png'
            result = subprocess.run(['timeout', '-k', '2', str(args.seconds + 5),
                                     str(ROOT / 'renderer/build/omaviz-render-probe'), str(source),
                                     str(output), str(args.seconds)],
                                    env=env, capture_output=True, text=True, timeout=args.seconds + 9)
            log = result.stdout + result.stderr
            assert result.returncode == 0 and not re.search(r'ReferenceError|TypeError|Failed to', log), log
            frames = re.search(r'scene_frame (\d+)', log)
            stream = re.search(r'scene_source "([^"]+)"', log)
            assert frames and int(frames[1]) > 30, f'{name}: no sustained live audio\n{log}'
            assert stream and stream[1] == 'pipewire', f'{name}: live PipeWire required\n{log}'
            selected_second = args.seconds
            if args.best_frame:
                candidates = [(output, args.seconds)] + [(Path(folder) / f'{name}-{i+1}.png', 2+i*.25) for i in range(3)]
                def brightness(candidate):
                    return float(subprocess.check_output(['magick', str(candidate[0]), '-format', '%[fx:mean]', 'info:'], text=True))
                output, selected_second = max(candidates, key=brightness)
            shutil.copyfile(output, SHOTS / f'{name}.png')
            data['captures'] = [c for c in data['captures'] if c['file'] != f'{name}.png']
            data['captures'].append({'file': f'{name}.png', 'mode': mode, 'dimensions': [width, height],
                                     'audible_frames': int(frames[1]), 'source': 'Live PipeWire system audio; production VisualCanvas/native renderer; no synthetic input',
                                     'captured_at': datetime.now(timezone.utc).isoformat(),
                                     'duration_seconds': args.seconds, 'options': options})
            data['captures'][-1]['sensitivity'] = args.gain
            data['captures'][-1]['selected_frame_seconds'] = selected_second
            provenance.write_text(json.dumps(data, indent=2) + '\n')
            print(f'{name}: captured {frames[1]} live PipeWire frames at {width}×{height}', flush=True)

if __name__ == '__main__':
    main()
