#version 310 es
precision highp float;
// omaviz GPU visualizer — Winamp-style spectrum (v7.5).
// Compiled to visual.qsb by build.sh. Data via 32x12 RGBA texture.
// Row centers: y=(i+0.5)/12
//   row 0  spectrum magnitudes (R)
//   row 1  peak-hold magnitudes (R)  [JS-maintained]
//   row 2  R=visual(0 analyzer /1 scope) G=colorSrc(0 theme /1 custom) B=unused
//   row 3  R=time(loop 0..1) G=unused B=unused   (time lives in .r, not .g)
//   row 4  R=border(0/1) G=unused B=unused
//   row 5  custom color RGB
//   row 6  theme bottom RGB
//   row 7  theme top RGB
//   row 8  R=fire(0/1, >0.5 == on) G=unused B=unused
//   row 9  R=peaks(0/1, >0.5 == on) G=falloff(0..1) B=unused A=unused
//   row 10 R=alpha(0..1) G=unused B=unused   (bar opacity)
//   row 11 R=scopeStyle(0 line/1 dot) G=scopeColorMode(0 solid) B=scopeGrid(0/1)
// Qt6 ShaderEffect provides the default vertex shader + qt_TexCoord0.

layout(location = 0) in vec2 qt_TexCoord0;
layout(binding = 1) uniform sampler2D u_tex;
layout(location = 0) out vec4 fragColor;

const float H = 12.0;
const float NB = 32.0;
float bandAt(float x) { return texture(u_tex, vec2(clamp(x,0.0,1.0), 0.5/H)).r; }
float peakAt(float x) { return texture(u_tex, vec2(clamp(x,0.0,1.0), 1.5/H)).r; }
vec4  ctrl() { return texture(u_tex, vec2(0.5, 2.5/H)); }
vec4  meta() { return texture(u_tex, vec2(0.5, 3.5/H)); }
vec4  opts() { return texture(u_tex, vec2(0.5, 4.5/H)); }
vec3  cust() { return texture(u_tex, vec2(0.5, 5.5/H)).rgb; }
vec3  cBot() { return texture(u_tex, vec2(0.5, 6.5/H)).rgb; }
vec3  cTop() { return texture(u_tex, vec2(0.5, 7.5/H)).rgb; }
vec4  fireRow() { return texture(u_tex, vec2(0.5, 8.5/H)); }
vec4  peaksRow() { return texture(u_tex, vec2(0.5, 9.5/H)); }
vec4  alphaRow() { return texture(u_tex, vec2(0.5, 10.5/H)); }
vec4  scopeRow() { return texture(u_tex, vec2(0.5, 11.5/H)); }

float gap() { return opts().r > 0.5 ? 0.10 : 0.0; }
float barWidth() { return (1.0 - gap()) / NB; }
float barCenter(float bx) { return (bx + 0.5) / NB; }

// FIX (v7.5): toggles were painted as 0/255 (-> 0.0/1.0) but decoded with
// int(r*2+0.5)==1, which reads 1.0 as 2 -> fire/peaks never turned on.
// Decode with > 0.5 so the painted 1.0 is correctly "on".
bool fireOn() { return fireRow().r > 0.5; }
bool peaksOn() { return peaksRow().r > 0.5; }
float falloff() { return peaksRow().g; }

// Fire palette (Winamp-ish flame), THEME-SOURCED per THEME_PALETTE.md.
// t: 0 at flame base (white-hot core) -> 1 at cooling ember tip.
// cBot()/cTop() are the active Omarchy theme gradient (Matte Black:
// accent #e68e0d -> bright_blue #f59e0b), so the flame tracks the theme
// instead of a hardcoded amber/red.
vec3 fireColor(float t) {
  vec3 core = mix(vec3(1.0, 0.95, 0.8), cBot(), 0.35); // white-hot near accent
  vec3 mid  = cBot();                                  // accent orange
  vec3 tip  = cTop() * 0.55;                           // cooler ember from bright_blue
  vec3 col = mix(core, mid, smoothstep(0.0, 0.35, t));
  col = mix(col, tip, smoothstep(0.35, 1.0, t));
  return col;
}

// Theme gradient for a normalized height t (0 at bar bottom -> 1 at bar top).
// Uses the active Omarchy theme's accent (bottom) -> a brighter shade (top).
// themeBottom/themeTop are seeded from THEME_PALETTE.md (active Omarchy theme).
vec3 themeColor(float t) {
  if (int(ctrl().g * 2.0 + 0.5) == 1) return cust(); // custom color
  return mix(cBot(), cTop(), clamp(t*0.95+0.05, 0.0, 1.0));
}

// Dynamic background: dark base with subtle theme-tinted gradient.
vec3 background(vec2 uv, float t) {
  float time = meta().r * 500.0;   // time lives in .r (loop 0..1)
  vec3 baseCol = mix(cBot()*0.15, cTop()*0.08, uv.y);
  float vig = 1.0 - 0.35 * length(uv - vec2(0.5,0.5));
  float shimmer = 0.02 * sin(uv.x * 6.0 + time * 0.01);
  return clamp(baseCol + shimmer, 0.0, 1.0) * vig;
}

void main() {
  vec2 uv = qt_TexCoord0;
  float x = uv.x, y = uv.y;

  // ---- Background ----
  vec3 col = background(uv, x);
  if (peaksOn()) {
    float extraGlow = 0.0;
    for (int i = 0; i < 32; i++) {
      float pk = peakAt(float(i) / 31.0);
      extraGlow += pk * 0.015;
    }
    col += vec3(1.0) * extraGlow * 0.15;
  }

  // ---- Bars / Fire ----
  int visual = int(ctrl().r * 2.0 + 0.5);
  bool fire = fireOn();
  if (visual == 0) { // Analyzer
    float bx = floor(x * NB);
    float lx = fract(x * NB);
    float v = bandAt(barCenter(bx));

    if (fire) {
      // ---- Winamp-style 2D fluid/drip fire (no 3D) ----
      float t = meta().r * 6.2831;            // looping time phase (.r channel)
      float yy = 1.0 - y;                      // 0 at bottom, 1 at top
      // per-column flicker (no 3D)
      float flick = 0.5*sin(bx*1.7 + t*1.7)
                  + 0.5*sin(bx*3.3 - t*1.1)
                  + 0.5*sin(bx*0.7 + t*0.6);
      flick /= 1.5;                            // ~ -1..1
      float flameH = clamp(v * (0.85 + 0.25*flick), 0.0, 1.0);
      if (flameH < 0.02) flameH = 0.0;
      // filled flame body with soft top edge
      float body = smoothstep(flameH, flameH - 0.18, yy);
      // rising drip tongues (subtract a moving notch)
      float drip = 0.14 * (0.5 + 0.5*sin(bx*2.3 - t*2.0)) * step(yy, flameH);
      body = max(body - drip, 0.0);
      float ct = clamp(yy / max(flameH, 0.001), 0.0, 1.0); // 0 base -> 1 tip
      vec3 fc = fireColor(ct);
      // white-hot core at the very base
      fc = mix(vec3(1.0, 0.95, 0.8), fc, smoothstep(0.0, 0.16, yy));
      col += fc * body;
    } else {
      // ---- Solid bars (Winamp-style, 2D) ----
      float h = v * 0.96;
      float bottom = 1.0 - h;
      float insideF = step(lx, barWidth()) * step(bottom, y);
      bool inside = insideF > 0.5;
      vec3 barCol = themeColor((y - bottom) / max(h, 0.001));
      // faint outer edge
      float edge = smoothstep(barWidth()*0.92, barWidth()*0.85, lx) * insideF;
      col += barCol * edge * 0.15;
      if (inside) {
        col += barCol;
        col += barCol * smoothstep(0.02, 0.0, abs(y - bottom)) * step(h, 0.99);
      }
    }
  } else {
    // Oscilloscope — render-side branch, kept functional.
    int   sStyle  = int(scopeRow().r * 2.0 + 0.5);  // 0 line, 1 dot
    int   sColor  = int(scopeRow().g * 2.0 + 0.5);  // 0 solid
    bool  sGrid   = scopeRow().b > 0.5;
    float sThick  = clamp(alphaRow().g, 0.0, 1.0); // thickness 0..1
    float env = 0.0;
    for (int i = 0; i < 32; i++) env += bandAt(float(i) / 31.0);
    env /= 32.0;
    float w = env * 0.9;
    float ph = x * 12.0 + meta().r * 4.0;
    float wave = sin(ph) * w + 0.15 * sin(ph * 3.0 + 1.0) * w;
    float wy = 0.5 + wave * 0.45;
    float d = abs(y - wy);
    float lw = (sThick * 0.02) + 0.004;
    vec3 sc = themeColor(y);
    if (sStyle == 1) {
      float dd = length(vec2((fract(x*NB)-0.5), d));
      if (dd < lw) col = sc;
    } else {
      if (d < lw) col = sc;
    }
    if (sGrid) {
      col += vec3(0.18) * (
        step(0.002, abs(fract(y*8.0)-0.5)-0.48)*0.5 +
        step(0.002, abs(fract(x*10.0)-0.5)-0.48)*0.5);
    }
  }

  fragColor = vec4(col, 1.0);
}
