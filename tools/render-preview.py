#!/usr/bin/env python3
"""Compose marketplace artwork from genuine live-audio native screenshots.

Regeneration preserves screenshot proportions and never redraws a visualization.
Run tools/capture-preview.py first; Mini/Settings are actual desktop captures.
"""
from base64 import b64encode
from html import escape
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SHOTS = ROOT / 'docs/screenshots/marketing'
PARTS = []


def add(svg):
    PARTS.append(svg)


def text(value, x, y, size=24, color='#b4bdcc', weight=400, spacing=0):
    add(f'<text x="{x}" y="{y}" fill="{color}" font-family="Adwaita Sans, DejaVu Sans, sans-serif" '
        f'font-size="{size}" font-weight="{weight}" letter-spacing="{spacing}">{escape(value)}</text>')


def image(name, x, y, width, height, align='xMidYMid'):
    payload = b64encode((SHOTS / f'{name}.png').read_bytes()).decode()
    add(f'<image href="data:image/png;base64,{payload}" x="{x}" y="{y}" '
        f'width="{width}" height="{height}" preserveAspectRatio="{align} meet"/>')


def frame(x, y, width, height):
    add(f'<rect x="{x}" y="{y}" width="{width}" height="{height}" '
        'fill="#080b11" stroke="#28303d" stroke-width="1.5"/>')


def tile(name, label, x, y, height, accent):
    frame(x, y, 565, height)
    add(f'<rect x="{x+20}" y="{y+24}" width="4" height="23" fill="{accent}"/>')
    text(label, x+38, y+44, 27, '#edf1f8', 500)
    image(name, x+16, y+64, 533, height-80)


add('<svg xmlns="http://www.w3.org/2000/svg" width="2400" height="1800" viewBox="0 0 2400 1800">')
add('<rect width="2400" height="1800" fill="#080a0f"/>')
add('<path d="M64 32H2336" stroke="#d7a05b" stroke-width="3"/>')
text('OMAVIZ', 60, 151, 112, '#f5f6fa', 600, -5)
text('Your music, in motion.', 66, 215, 38, '#bdc7d7', 400, -.5)

frame(1840, 66, 496, 150)
text('ALWAYS IN YOUR BAR', 1862, 101, 18, '#a9b6c9', 500, 2)
image('Mini', 1862, 119, 452, 70)

frame(64, 250, 1736, 432)
text('COSMOS', 84, 291, 26, '#edf1f8', 500, 1)
text('DRIFT INTO DEEP SPACE', 1430, 291, 18, '#a2b2cc', 500, .5)
image('Cosmos', 80, 310, 1704, 356)

for name, label, col, accent in [
    ('Spikes', 'Spectrum / Flames', 0, '#ffb36b'),
    ('Tunnel', 'Tunnel', 1, '#b5c4df'),
    ('Spiral', 'Spiral', 2, '#b697f2'),
]:
    tile(name, label, 64+585*col, 708, 296, accent)
for name, label, col, accent in [
    ('Siri', 'Siri', 0, '#78d9ff'),
    ('Strings', 'Strings', 1, '#dfc38e'),
    ('Waves', 'Waves', 2, '#71d6bf'),
]:
    tile(name, label, 64+585*col, 1024, 280, accent)
for name, label, col, accent in [
    ('Bokeh', 'Bokeh', 0, '#b4c8f1'),
    ('PixelWave', 'Pixel Wave', 1, '#bd9ce9'),
    ('Orbit', 'Orbit', 2, '#dfba89'),
]:
    tile(name, label, 64+585*col, 1324, 296, accent)

frame(1840, 250, 496, 650)
text('MAKE IT YOURS', 1862, 291, 21, '#d9e1ed', 500, 1.5)
image('Settings', 1856, 316, 464, 560, 'xMidYMin')
for name, label, y in [
    ('Spectrum', 'SPECTRUM / BARS', 920),
    ('Stacks', 'SPECTRUM / STACKS', 1156),
    ('ClassicSiri', 'CLASSIC SIRI', 1392),
]:
    frame(1840, y, 496, 228)
    text(label, 1862, y+36, 19, '#c9d3e3', 500, 1)
    image(name, 1856, y+58, 464, 154)

add('<path d="M64 1670H2336" stroke="#293345" stroke-width="1"/>')
text('10 VISUALIZATIONS', 64, 1715, 22, '#f1f4fa', 600, 1)
text('MINI  /  PREVIEW  /  DESKTOP', 660, 1715, 22, '#bdc9dc', 500, 1)
text('LIVE AUDIO  ·  TRACK SHUFFLE  ·  YOUR COLORS', 1495, 1715, 20, '#a6b5cb', 500, .5)
text('Captured live on Omarchy.', 64, 1760, 18, '#8190a6')
text('Milky Way: ESO/S. Brunier · CC BY 4.0', 1600, 1760, 19, '#a0adc0')
add('</svg>')

with tempfile.TemporaryDirectory(prefix='omaviz-preview-') as directory:
    source = Path(directory) / 'preview.svg'
    source.write_text('\n'.join(PARTS))
    subprocess.run(['rsvg-convert', str(source), '-o', str(ROOT / 'preview.png')], check=True)
print('Rendered preview.png from live native screenshots (2400×1800).')
