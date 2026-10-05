#!/usr/bin/env python3
"""Compose the marketplace preview from current native captures without stretching."""
from base64 import b64encode
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def image(name, x, y, width, height):
    data = (ROOT / 'docs' / 'screenshots' / name).read_bytes()
    return (f'<image href="data:image/png;base64,{b64encode(data).decode()}" '
            f'x="{x}" y="{y}" width="{width}" height="{height}" '
            'preserveAspectRatio="xMidYMid meet"/>')


def label(text, x, y, size=25, color='#aeb9cd'):
    return (f'<text x="{x}" y="{y}" fill="{color}" font-family="DejaVu Sans" '
            f'font-size="{size}">{text}</text>')


svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="2400" height="1500">
<rect width="2400" height="1500" fill="#0c1019"/>
<rect width="2400" height="7" fill="#57cbe7"/>
{label('OMARCHY AUDIO VISUALIZER',80,85,25,'#57cbe7')}
{label('OMAVIZ',75,205,108,'#f5f7fc')}
{label('Your music. A living desktop.',82,264,32)}
{label('NATIVE GPU · PIPEWIRE · QUICKSHELL',1650,85,22)}
{label('FIRE SPECTRUM · REFLECTION + PEAKS',80,350,26,'#edb356')}
{image('Spectrum-v8.6.1.png',80,385,1440,480)}
{label('STRINGS',80,950,24,'#ddc38f')}
{label('WAVES',840,950,24,'#edb356')}
{image('Strings-v8.6.1.png',80,980,680,227)}
{image('Waves-v8.6.1.png',840,980,680,227)}
{label('SIRI',80,1280,24,'#57cbe7')}
{image('Siri-v8.6.1.png',80,1300,500,167)}
{label('Four visualizations. Your palette.',650,1370,29,'#f5f7fc')}
{label('Mini, preview, and desktop.',650,1420,26)}
{label('LIVE SETTINGS · v8.6.1',1620,350,26,'#edb356')}
{image('Settings-v8.6.1.png',1620,385,700,960)}
{label('Live PipeWire spectrum · 2.2× Response · waveform examples use controlled audio',80,1490,18,'#8490a6')}
</svg>'''
source = ROOT / 'tools' / '.preview-render.svg'
try:
    source.write_text(svg)
    subprocess.run(['rsvg-convert', str(source), '-o', str(ROOT / 'preview.png')], check=True)
finally:
    source.unlink(missing_ok=True)
