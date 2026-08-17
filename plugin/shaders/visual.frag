#version 310 es
precision highp float;
// omaviz GPU visualizer fragment shader (GLSL ES 310, Qt6 qsb).
// Compiled to visual.qsb by build.sh.
//
// Data arrives via a single 32x7 RGBA texture (u_tex). With H=7 rows, the
// center of row i is at y=(i+0.5)/7:
//   row 0 (y=0.071): spectrum band magnitudes in R (0..1)
//   row 1 (y=0.214): R=visual G=style B=color
//   row 2 (y=0.357): R=peak G=time B=colorSrc(0 theme /1 custom)
//   row 3 (y=0.500): R=border G=render3d B=unused
//   row 4 (y=0.643): custom color RGB
//   row 5 (y=0.786): theme bottom color RGB
//   row 6 (y=0.929): theme top color RGB
// Qt6 ShaderEffect provides the default vertex shader + qt_TexCoord0.

layout(location = 0) in vec2 qt_TexCoord0;
layout(binding = 1) uniform sampler2D u_tex;
layout(location = 0) out vec4 fragColor;

const float H = 7.0;
float bandAt(float x) { return texture(u_tex, vec2(clamp(x,0.0,1.0), 0.5/H)).r; }
vec4  ctrl() { return texture(u_tex, vec2(0.5, 1.5/H)); }
vec4  meta() { return texture(u_tex, vec2(0.5, 2.5/H)); }
vec4  opts() { return texture(u_tex, vec2(0.5, 3.5/H)); }
vec3  cust() { return texture(u_tex, vec2(0.5, 4.5/H)).rgb; }
vec3  cBot() { return texture(u_tex, vec2(0.5, 5.5/H)).rgb; }
vec3  cTop() { return texture(u_tex, vec2(0.5, 6.5/H)).rgb; }

// Vertical theme gradient (bottom -> top). Used for bars & wave.
vec3 themeColor(float t) {
  if (int(meta().b * 2.0 + 0.5) == 1) return cust();   // custom color
  return mix(cBot(), cTop(), clamp(t, 0.0, 1.0));
}

void main() {
  vec2 uv = qt_TexCoord0;        // x:0..1 left->right, y:0..1 top->bottom
  float x = uv.x;
  float y = uv.y;
  vec3 col = vec3(0.0);

  int   visual = int(ctrl().r * 2.0 + 0.5);   // 0 bars, 1 wave
  int   style  = int(ctrl().g * 2.0 + 0.5);   // 0 classic, 1 fire
  float peak   = meta().r;
  float time   = meta().g;
  bool  border = opts().r > 0.5;
  bool  is3d   = opts().g > 0.5;

  float gap = border ? 0.15 : 0.0;
  float NB  = 32.0;
  float bx  = floor(x * NB);
  float lx  = fract(x * NB);
  float bcenter = (bx + 0.5) / NB;

  if (visual == 1) {
    // WAVE: mirrored sine ribbon driven by the spectrum envelope
    float env = 0.0;
    for (int i = 0; i < 32; i++) env += bandAt(float(i) / 31.0);
    env /= 32.0;
    float w = (0.04 + env * 0.16) * sin(x * 3.14159);
    float ph = x * 40.0 + time * 3.0;
    float rib = 0.5 + 0.42 * w * sin(ph);
    float d = abs(y - rib);
    float line = smoothstep(0.012, 0.0, d);
    vec3 wc = themeColor(0.7);
    col = wc * line;
    col += wc * 0.10 * smoothstep(0.06, 0.0, d);
  } else if (style == 1) {
    // FIRE: discrete flames rising from the BOTTOM (y=1) up to y=1-h.
    float vv = bandAt(bcenter);
    float h = max(0.06, vv * 0.98);
    float bottom = 1.0 - h;
    float inside = step(lx, 1.0 - gap) * step(bottom, y);
    float t = (y - bottom) / max(h, 0.001);   // 0 tip, 1 base
    float fl = 0.6 + 0.4 * sin(x * 18.0 + time * 5.0 + t * 6.0);
    float flame = inside * (0.5 + 0.5 * t) * fl;
    vec3 fc = mix(vec3(1.0, 0.95, 0.55), vec3(1.0, 0.35, 0.05), pow(1.0 - t, 1.2));
    fc = mix(fc, vec3(0.85, 0.06, 0.0), pow(1.0 - t, 3.0));
    col = fc * flame * 1.6;
    col += vec3(1.0, 0.6, 0.2) * 0.25 * smoothstep(0.12, 0.0, 1.0 - y) * step(lx, 1.0 - gap) * step(bottom, y);
  } else {
    // BARS (classic): discrete vertical bars rising from the bottom.
    float v = bandAt(bcenter);
    float h = v * 0.96;
    float bottom = 1.0 - h;
    float inside = step(lx, 1.0 - gap) * step(bottom, y);
    // Vertical theme gradient: base = cBot, tip = cTop.
    vec3 bc = themeColor((y - bottom) / max(h, 0.001));
    if (is3d) bc *= 1.0 - 0.35 * (1.0 - lx / max(1.0 - gap, 0.001));
    col = bc * inside;
    // bright cap line on top
    col += bc * smoothstep(0.025, 0.0, abs(y - bottom)) * step(h, 0.99) * step(lx, 1.0 - gap);
  }

  col *= (1.0 + 0.15 * peak * (1.0 - y));
  fragColor = vec4(col, 1.0);
}
