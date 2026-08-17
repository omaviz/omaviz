#version 310 es
precision highp float;
// omaviz GPU visualizer fragment shader (GLSL ES 310, Qt6 qsb).
// Compiled to visual.qsb by build.sh. Data arrives via a 32x12 RGBA texture.
// Row centers: y=(i+0.5)/12
//   row 0  spectrum magnitudes (R)
//   row 1  peak-hold magnitudes (R)  [JS-maintained]
//   row 2  R=visual(0 analyzer /1 scope) G=colorSrc(0 theme /1 custom) B=unused
//   row 3  R=time G=unused B=unused
//   row 4  R=border G=render3d B=unused
//   row 5  custom color RGB
//   row 6  theme bottom RGB
//   row 7  theme top RGB
//   row 8  R=eqMode(0 bars/1 lines) G=eqColor(0 solid/1 line/2 fade/3 fire) B=eqGrid
//   row 9  R=eqPeaks G=eqFalloff(0..1) B=eqZoom(0 1x/1 2x/2 4x)
//   row 10 R=scopeStyle(0 line/1 dot) G=scopeColor(0-3) B=scopeGrid
//   row 11 R=scopeScan G=scopeCentered B=scopeThickness(1..4)
// Qt6 ShaderEffect provides the default vertex shader + qt_TexCoord0.

layout(location = 0) in vec2 qt_TexCoord0;
layout(binding = 1) uniform sampler2D u_tex;
layout(location = 0) out vec4 fragColor;

const float H = 12.0;
float bandAt(float x) { return texture(u_tex, vec2(clamp(x,0.0,1.0), 0.5/H)).r; }
float peakAt(float x) { return texture(u_tex, vec2(clamp(x,0.0,1.0), 1.5/H)).r; }
vec4  ctrl() { return texture(u_tex, vec2(0.5, 2.5/H)); }
vec4  meta() { return texture(u_tex, vec2(0.5, 3.5/H)); }
vec4  opts() { return texture(u_tex, vec2(0.5, 4.5/H)); }
vec3  cust() { return texture(u_tex, vec2(0.5, 5.5/H)).rgb; }
vec3  cBot() { return texture(u_tex, vec2(0.5, 6.5/H)).rgb; }
vec3  cTop() { return texture(u_tex, vec2(0.5, 7.5/H)).rgb; }
vec4  eq1()  { return texture(u_tex, vec2(0.5, 8.5/H)); }
vec4  eq2()  { return texture(u_tex, vec2(0.5, 9.5/H)); }
vec4  sc1()  { return texture(u_tex, vec2(0.5, 10.5/H)); }
vec4  sc2()  { return texture(u_tex, vec2(0.5, 11.5/H)); }

// grid helper
float gridLine(float x, float y) {
  float gx = step(0.002, abs(fract(x * 10.0) - 0.5) - 0.48);
  float gy = step(0.002, abs(fract(y * 8.0) - 0.5) - 0.48);
  return (1.0 - gx) * 0.5 + (1.0 - gy) * 0.5;
}

// Color for a given normalized height t (0 bottom -> 1 top). Theme gradient
// unless custom color source selected.
vec3 vColor(float t) {
  if (int(ctrl().g * 2.0 + 0.5) == 1) return cust();
  return mix(cBot(), cTop(), clamp(t, 0.0, 1.0));
}

// Fire palette for analyzer (Winamp "Fire" color mode).
vec3 fireColor(float h) {
  return mix(vec3(1.0, 0.95, 0.55), vec3(1.0, 0.35, 0.05), pow(1.0 - h, 1.2));
}

// Map a band index 0..31 to a zoomed x given eqZoom (1x/2x/4x). Winamp 2x/4x
// show a narrower, zoomed frequency range (higher frequencies).
float zoomX(float x, int zoom) {
  if (zoom == 1) return x * 0.5;          // 2x: top half of spectrum
  if (zoom == 2) return 0.5 + x * 0.5;    // 4x: upper quarter-ish
  return x;
}

void main() {
  vec2 uv = qt_TexCoord0;
  float x = uv.x, y = uv.y;
  vec3 col = vec3(0.0);

  int   visual = int(ctrl().r * 2.0 + 0.5);
  bool  border = opts().r > 0.5;
  bool  is3d   = opts().g > 0.5;
  float gap = border ? 0.15 : 0.0;
  float NB = 32.0;
  float bx = floor(x * NB);
  float lx = fract(x * NB);
  float bcenter = (bx + 0.5) / NB;

  if (visual == 1) {
    // ================= OSCILLOSCOPE =================
    int   sStyle = int(sc1().r * 2.0 + 0.5);
    int   sColor = int(sc1().g * 2.0 + 0.5);
    bool  sGrid  = sc1().b > 0.5;
    bool  sScan  = sc2().r > 0.5;
    bool  sCtr   = sc2().g > 0.5;
    float th     = sc2().b;                       // 1..4
    float amp = bandAt(x);                        // 0..1 audio level proxy
    // Reconstruct a waveform: Winamp scope draws the time-domain signal. We
    // synthesize a plausible wave from the spectrum envelope + phase.
    float env = 0.0;
    for (int i = 0; i < 32; i++) env += bandAt(float(i) / 31.0);
    env /= 32.0;
    float w = env * 0.9;
    float ph = x * 12.0 + meta().g * 4.0;
    float wave = sin(ph) * w + 0.15 * sin(ph * 3.0 + 1.0) * w;
    if (sCtr) wave = wave;                        // centered around 0.5
    float wy = 0.5 + wave * 0.45;
    float d = abs(y - wy);
    float lw = (th / NB) * 1.2 + 0.004;
    vec3 sc = (sColor == 3) ? fireColor(clamp(y, 0.0, 1.0))
             : (sColor == 0 ? vColor(y) : vColor(y));
    if (sColor == 2) { // fade blocks: fade with distance
      sc *= (0.4 + 0.6 * (1.0 - d));
    }
    if (sStyle == 1) { // dot
      float dd = length(vec2((lx - 0.5), d));
      if (dd < lw) col = sc;
    } else {          // line
      if (d < lw) col = sc;
    }
    if (sScan) { // sweep beam: brighten near a moving x
      float sx = fract(meta().g * 0.5);
      col += sc * 0.5 * smoothstep(0.03, 0.0, abs(x - sx));
    }
    if (sGrid) col += vec3(0.18) * gridLine(x, y);
  } else {
    // ================= SPECTRUM ANALYZER =================
    int   eMode  = int(eq1().r * 2.0 + 0.5);   // 0 bars, 1 lines
    int   eColor = int(eq1().g * 2.0 + 0.5);   // 0 solid 1 line 2 fade 3 fire
    bool  eGrid  = eq1().b > 0.5;
    bool  ePeaks = eq2().r > 0.5;
    float fall   = eq2().g;
    int   zoom   = int(eq2().b * 2.0 + 0.5);
    float th     = 2.0;

    if (eMode == 1) {
      // LINES: connected spectrum curve
      float zx = zoomX(x, zoom);
      float v = bandAt(zx);
      float wy = 1.0 - v * 0.96;
      float d = abs(y - wy);
      float lw = 0.006 + th * 0.002;
      vec3 lc = (eColor == 3) ? fireColor(v) : ((eColor == 1 || eColor == 2) ? vColor(v) : vColor(v));
      if (eColor == 2) lc *= (0.4 + 0.6 * (1.0 - d));
      if (d < lw) col = lc;
    } else {
      // BARS: discrete bars rising from bottom
      float zx = zoomX(bcenter, zoom);
      float v = bandAt(zx);
      float h = v * 0.96;
      float bottom = 1.0 - h;
      float inside = step(lx, 1.0 - gap) * step(bottom, y);
      vec3 bc = (eColor == 3) ? fireColor((y - bottom) / max(h, 0.001))
               : vColor((y - bottom) / max(h, 0.001));
      if (eColor == 2) bc *= (0.5 + 0.5 * (y - bottom) / max(h, 0.001)); // fade blocks
      if (is3d) bc *= 1.0 - 0.35 * (1.0 - lx / max(1.0 - gap, 0.001));
      col = bc * inside;
      // bright cap
      col += bc * smoothstep(0.025, 0.0, abs(y - bottom)) * step(h, 0.99) * step(lx, 1.0 - gap);
      // peak-hold line
      if (ePeaks) {
        float pk = peakAt(zx);
        float pky = 1.0 - pk * 0.96;
        col += bc * smoothstep(0.012, 0.0, abs(y - pky)) * step(lx, 1.0 - gap);
      }
    }
    if (eGrid) {
      // grid lines (faint)
      float gy = step(0.002, abs(fract(y * 8.0) - 0.5) - 0.48);
      col += vec3(0.12) * (1.0 - gy) * 0.5;
    }
  }

  fragColor = vec4(col, 1.0);
}
