#!/usr/bin/env python3
"""Compose the marketplace preview from unaltered Omaviz screenshots."""
from base64 import b64encode
from math import exp, sin
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def png(name):
    data = (ROOT / "docs" / "screenshots" / name).read_bytes()
    return "data:image/png;base64," + b64encode(data).decode("ascii")


def image(name, x, y, width, height, mask=""):
    masked = f' mask="url(#{mask})"' if mask else ""
    return (f'<image href="{png(name)}" x="{x}" y="{y}" width="{width}" '
            f'height="{height}" preserveAspectRatio="none"{masked}/>')


# A quiet equalizer ghost gives the lower-right whitespace an audio cue while
# leaving the real settings screenshot and mode captures as the focal points.
pattern_bars = []
for index in range(35):
    x = 1664 + index * 20
    envelope = exp(-((index - 19) / 18) ** 2)
    height = 16 + (35 + 90 * sin(index * .49) ** 2) * envelope
    y = 1470 - height
    opacity = .055 + .13 * envelope
    color = "#f5b338" if index > 17 else "#d96825"
    pattern_bars.append(f'<rect x="{x}" y="{y:.1f}" width="4" height="{height:.1f}" rx="2" fill="{color}" opacity="{opacity:.3f}"/>')
pattern = "".join(pattern_bars)

svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="2400" height="1500" viewBox="0 0 2400 1500">
<defs>
  <linearGradient id="background" x1="0" y1="0" x2="1" y2="1">
    <stop stop-color="#10131d"/><stop offset=".52" stop-color="#080b12"/><stop offset="1" stop-color="#130e19"/>
  </linearGradient>
  <radialGradient id="orangeGlow"><stop stop-color="#dd5b12" stop-opacity=".16"/><stop offset="1" stop-color="#dd5b12" stop-opacity="0"/></radialGradient>
  <radialGradient id="violetGlow"><stop stop-color="#7942b6" stop-opacity=".13"/><stop offset="1" stop-color="#7942b6" stop-opacity="0"/></radialGradient>
  <linearGradient id="accent"><stop stop-color="#c3190b"/><stop offset=".5" stop-color="#f07d0e"/><stop offset="1" stop-color="#f4d449"/></linearGradient>
  <linearGradient id="leftFeather"><stop stop-color="black"/><stop offset=".035" stop-color="white"/><stop offset=".96" stop-color="white"/><stop offset="1" stop-color="black"/></linearGradient>
  <mask id="heroMask"><rect x="55" y="306" width="1565" height="410" fill="url(#leftFeather)"/></mask>
  <mask id="leftSmall"><rect x="78" y="990" width="720" height="520" fill="url(#leftFeather)"/></mask>
  <mask id="rightSmall"><rect x="870" y="990" width="720" height="520" fill="url(#leftFeather)"/></mask>
</defs>
<rect width="2400" height="1500" fill="url(#background)"/>
<ellipse cx="860" cy="300" rx="1000" ry="600" fill="url(#orangeGlow)"/>
<ellipse cx="2020" cy="1420" rx="800" ry="580" fill="url(#violetGlow)"/>
<rect width="2400" height="7" fill="url(#accent)"/>

<text x="91" y="96" fill="#f4a32d" font-family="DejaVu Sans" font-size="27" font-weight="bold" letter-spacing="5">OMARCHY AUDIO VISUALIZER</text>
<text x="82" y="218" fill="#f8f6f2" font-family="DejaVu Sans" font-size="116" font-weight="bold" letter-spacing="-5">OMAVIZ</text>
<text x="93" y="268" fill="#d4d8e1" font-family="DejaVu Sans" font-size="33">Your music. A living desktop.</text>
<text x="2260" y="100" text-anchor="end" fill="#b9bdc9" font-family="DejaVu Sans" font-size="22" letter-spacing="2">PIPEWIRE / QUICKSHELL</text>
<text x="2260" y="146" text-anchor="end" fill="#e6a043" font-family="DejaVu Sans" font-size="20" letter-spacing="2">BAR WIDGET + DETACHABLE WINDOW</text>

{image('Amber-spectrum-horizontal.png',55,310,1560,401,'heroMask')}
<text x="90" y="760" fill="#f2aa3d" font-family="DejaVu Sans" font-size="23" font-weight="bold" letter-spacing="3">SPECTRUM · HORIZONTAL GRADIENT</text>
<text x="84" y="835" fill="#f6f3f1" font-family="DejaVu Sans" font-size="55" font-weight="bold">Every beat has a shape.</text>
<text x="90" y="879" fill="#aeb3bf" font-family="DejaVu Sans" font-size="23">Flame, custom palettes, and a live waveform — tuned in the app.</text>

<text x="90" y="972" fill="#c7e88f" font-family="DejaVu Sans" font-size="20" font-weight="bold" letter-spacing="2">CUSTOM PALETTE</text>
<text x="879" y="972" fill="#f6a858" font-family="DejaVu Sans" font-size="20" font-weight="bold" letter-spacing="2">FLAME</text>
{image('Green-spectrum.png',78,1001,720,156,'leftSmall')}
{image('Flame-horizontal.png',870,1001,720,156,'rightSmall')}

<text x="90" y="1248" fill="#f2cd70" font-family="DejaVu Sans" font-size="20" font-weight="bold" letter-spacing="2">OSCILLOSCOPE</text>
<text x="879" y="1248" fill="#f4aa68" font-family="DejaVu Sans" font-size="20" font-weight="bold" letter-spacing="2">STACKS</text>
{image('oscilloscope.png',78,1275,720,221,'leftSmall')}
{image('Flame-stacks-horizontal.png',870,1307,720,156,'rightSmall')}

<text x="1702" y="265" fill="#f2b447" font-family="DejaVu Sans" font-size="22" font-weight="bold" letter-spacing="3">LIVE SETTINGS</text>
{image('Settings-v8.4.5.png',1690,290,565,960)}
<g>{pattern}</g>
<text x="1674" y="1492" fill="#756c6b" font-family="DejaVu Sans" font-size="18" letter-spacing="2">SOUND IN MOTION</text>
</svg>'''

source = ROOT / "tools" / ".preview-render.svg"
try:
    source.write_text(svg)
    subprocess.run(["magick", "-background", "none", str(source), str(ROOT / "preview.png")], check=True)
finally:
    source.unlink(missing_ok=True)
