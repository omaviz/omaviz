#!/usr/bin/env python3
"""Compose the marketplace artwork from genuine live-audio native captures.

Sources live in docs/screenshots/marketing/. Regeneration never synthesizes or
repaints a visualization, and preserves each screenshot's aspect ratio.
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


def text(value, x, y, size=24, color='#b5bfd0', weight=400, spacing=0):
    add(f'<text x="{x}" y="{y}" fill="{color}" font-family="Adwaita Sans, DejaVu Sans, sans-serif" '
        f'font-size="{size}" font-weight="{weight}" letter-spacing="{spacing}">{escape(value)}</text>')


def image(name, x, y, width, height, align='xMidYMid'):
    payload = b64encode((SHOTS / f'{name}.png').read_bytes()).decode()
    add(f'<image href="data:image/png;base64,{payload}" x="{x}" y="{y}" '
        f'width="{width}" height="{height}" preserveAspectRatio="{align} meet"/>')


def frame(x, y, width, height, radius=18):
    add(f'<rect x="{x}" y="{y}" width="{width}" height="{height}" rx="{radius}" '
        'fill="#0c0c12" stroke="#28303e" stroke-width="1.5"/>')


def tile(name, title, number, x, y, width, height, accent):
    frame(x, y, width, height)
    text(f'{number:02}', x+24, y+38, 18, accent, 600, 1)
    text(title, x+68, y+39, 27, '#f2f5fc', 500)
    image(name, x+16, y+57, width-32, height-72)


add('<svg xmlns="http://www.w3.org/2000/svg" width="2400" height="1600" viewBox="0 0 2400 1600">')
add('''<defs>
 <radialGradient id="halo"><stop stop-color="#17233b" stop-opacity=".74"/><stop offset="1" stop-color="#080b12" stop-opacity="0"/></radialGradient>
 <linearGradient id="accent"><stop stop-color="#5be5e2"/><stop offset=".5" stop-color="#a58bff"/><stop offset="1" stop-color="#ffba70"/></linearGradient>
</defs>
<rect width="2400" height="1600" fill="#080b12"/>
<ellipse cx="1840" cy="80" rx="1000" ry="700" fill="url(#halo)"/>
<rect x="72" y="32" width="2256" height="3" fill="url(#accent)"/>
''')
text('OMARCHY AUDIO VISUALIZER', 72, 83, 20, '#70d8e7', 600, 3)
text('OMAVIZ', 66, 193, 112, '#f4f6fb', 600, -5)
text('Your music. A living desktop.', 74, 257, 38, '#b6c2d5', 400, -.5)

frame(1580, 82, 748, 180, 18)
text('ALWAYS IN YOUR BAR', 1610, 122, 19, '#a2afc5', 500, 2)
image('Mini', 1606, 144, 696, 62)
text('Live system audio. Right where you look.', 1610, 238, 22, '#c5cede')

# A large, instantly recognizable hero anchors the visual catalog.
frame(72, 320, 1664, 404)
text('01', 98, 361, 18, '#ffba70', 600, 1)
text('Spectrum', 142, 363, 28, '#f6f4ee', 500)
text('PEAKS + REFLECTION', 1435, 360, 17, '#c79e6b', 500, 1)
image('Spectrum', 92, 380, 1624, 326)

for data in [
    ('Siri', 'Siri', 2, 72, '#78d9ff'),
    ('Strings', 'Strings', 3, 633, '#e5c688'),
    ('Waves', 'Waves', 4, 1194, '#70e4d6'),
]:
    name, title, number, x, accent = data
    tile(name, title, number, x, 760, 541, 270, accent)

for data in [
    ('Bokeh', 'Bokeh', 5, 72, '#aac3ff'),
    ('PixelWave', 'Pixel Wave', 6, 633, '#bb9cff'),
    ('Orbit', 'Orbit', 7, 1194, '#ffbb85'),
]:
    name, title, number, x, accent = data
    tile(name, title, number, x, 1066, 541, 358, accent)

# This is the actual settings panel, not a reconstructed interface.
frame(1776, 320, 552, 1104)
text('MAKE IT YOURS', 1804, 361, 20, '#c7d4eb', 600, 2)
image('Settings', 1797, 392, 510, 822, 'xMidYMin')
text('Pick a look.', 1804, 1251, 33, '#f0f4ff', 500, -.5)
text('Make it move.', 1804, 1295, 33, '#f0f4ff', 500, -.5)
text('Colors, response, and geometry.', 1804, 1349, 21, '#a5b3c9')
text('Every change saves automatically.', 1804, 1382, 21, '#a5b3c9')

add('<path d="M72 1470H2328" stroke="#293345" stroke-width="1"/>')
text('7 VISUALIZATIONS', 72, 1513, 21, '#f2f5fc', 600, 1)
text('MINI  /  PREVIEW  /  DESKTOP', 570, 1513, 21, '#c2cee2', 500, 1)
text('NATIVE GPU  ·  YOUR COLORS  ·  YOUR MUSIC', 1425, 1513, 20, '#a9b6cd', 500, .5)
text('Actual Omaviz captures with live system audio.', 72, 1562, 19, '#7989a3')
text('github.com/omaviz/omaviz', 1958, 1562, 20, '#86d9e7', 500)
add('</svg>')

with tempfile.TemporaryDirectory(prefix='omaviz-preview-') as directory:
    source = Path(directory) / 'preview.svg'
    source.write_text('\n'.join(PARTS))
    subprocess.run(['rsvg-convert', str(source), '-o', str(ROOT / 'preview.png')], check=True)
print('Rendered preview.png from live native screenshots (2400×1600).')
