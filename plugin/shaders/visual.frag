#version 310 es
precision highp float;
// omaviz GPU visualizer fragment shader (GLSL ES 310, Qt6 qsb).
// Compiled to visual.qsb by build.sh.
//
// NO uniform blocks (Qt6 ShaderEffect UBO member upload is unreliable on this
// stack). All data arrives via a single 32x4 RGBA texture (u_tex):
//   row 0 (y=0.125): spectrum band magnitudes in R (0..1)
//   row 1 (y=0.375): R=u_visual G=u_style B=u_color A=u_scheme  (each 0..1)
//   row 2 (y=0.625): R=u_peak G=u_time(0..1)                       (each 0..1)
//   row 3 (y=0.875): unused
// Qt6 ShaderEffect provides the default vertex shader + qt_TexCoord0.

layout(location = 0) in vec2 qt_TexCoord0;
layout(binding = 1) uniform sampler2D u_tex;
layout(location = 0) out vec4 fragColor;

float bandAt(float x) {
  return texture(u_tex, vec2(clamp(x, 0.0, 1.0), 0.125)).r;
}
vec4 ctrl() { return texture(u_tex, vec2(0.5, 0.375)); }
vec4 meta() { return texture(u_tex, vec2(0.5, 0.625)); }

vec3 schemeColor(float h) {
  int scheme = int(meta().b * 3.0 + 0.5);   // scheme now in row 2 B channel
  if (scheme == 2) {
    if (h < 0.33) return vec3(0.16, 0.61, 0.95);
    if (h < 0.66) return vec3(0.48, 0.36, 0.89);
    return vec3(0.69, 0.35, 1.0);
  }
  if (scheme == 1) {
    if (h < 0.33) return vec3(1.0, 0.35, 0.11);
    if (h < 0.66) return vec3(1.0, 0.55, 0.10);
    return vec3(1.0, 0.81, 0.0);
  }
  if (h < 0.33) return vec3(0.16, 0.61, 0.95);
  if (h < 0.66) return vec3(0.60, 0.36, 0.89);
  return vec3(0.94, 0.35, 0.70);
}

vec3 fireColor(float t) {
  return mix(vec3(0.90, 0.05, 0.00), vec3(1.00, 0.95, 0.55), pow(t, 0.6));
}

void main() {
  vec2 uv = qt_TexCoord0;
  float x = uv.x;
  float y = uv.y;

  int   visual = int(ctrl().r * 2.0 + 0.5);   // 0 bars, 1 wave
  int   style  = int(ctrl().g * 2.0 + 0.5);   // 0 classic, 1 fire
  int   color  = int(ctrl().b * 2.0 + 0.5);   // 0 mono, 1 color
  float peak   = meta().r;
  float time   = meta().g;

  vec3 col = vec3(0.0);

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
    vec3 wc = color == 1 ? schemeColor(0.7) : vec3(0.86, 0.88, 0.92);
    col = wc * line;
    col += wc * 0.10 * smoothstep(0.06, 0.0, d);
  } else {
    // BARS (classic or fire)
    float v = bandAt(x);
    if (style == 1) {
      float top = v * 0.98;
      float core = smoothstep(top, top - 0.18, y);
      float flame = core;
      float pl = 0.5 + 0.5 * sin(x * 22.0 + time * 4.0 + y * 8.0);
      flame *= (0.75 + 0.25 * pl);
      vec3 fc = fireColor(y);
      col = fc * flame;
      col += vec3(1.0, 0.35, 0.12) * 0.12 * smoothstep(0.25, 0.0, y) * (0.4 + v);
    } else {
      // BARS (classic): discrete vertical bars with gaps, Winamp-style.
      // Divide x into N bars; sample the band at each bar's center.
      // QML y is top->bottom (0 at top), so bars rise from the BOTTOM:
      // a bar of height h occupies y in [1-h, 1].
      float NB = 32.0;
      float gap = 0.15;                    // fraction of cell that is gap
      float bx = floor(x * NB);            // which bar column
      float lx = fract(x * NB);            // position within the cell (0..1)
      float bcenter = (bx + 0.5) / NB;     // center of this bar
      float v = bandAt(bcenter);           // spectrum height at this bar
      float h = v * 0.96;                  // bar height from bottom
      float bottom = 1.0 - h;              // y at the bar's top (lower y)
      float inside = step(lx, 1.0 - gap) * step(bottom, y);
      vec3 bc = (color == 1) ? schemeColor(bcenter) : vec3(0.86, 0.88, 0.92);
      bc *= (0.45 + 0.55 * ((y - bottom) / max(h, 0.001)));   // brighter near the top of the bar
      col = bc * inside;
      // bright cap line on top of each bar
      col += bc * smoothstep(0.025, 0.0, abs(y - bottom)) * step(h, 0.99) * step(lx, 1.0 - gap);
    }
  }

  col *= (1.0 + 0.15 * peak * (1.0 - y));
  fragColor = vec4(col, 1.0);
}
