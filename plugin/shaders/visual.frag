#version 310 es
precision highp float;
// omaviz GPU visualizer — Winamp-style DENSE spectrum bars + WAVE ribbon field (v7.6).
// Compiled to visual.qsb by build.sh. Data via density x 12 RGBA texture.
// Row centers: y=(i+0.5)/12
//   row 0  spectrum magnitudes (R)
//   row 1  peak-hold magnitudes (R)  [JS-maintained]
//   row 2  R=visual(0 Bars /1 Oscilloscope /2 Wave)  G=colorSrc(0 theme/1 custom)  B=unused
//   row 3  R=time(loop 0..1) G=unused B=unused
//   row 4  R=border(0/1) G=unused B=unused
//   row 5  custom color RGB
//   row 6  theme bottom RGB
//   row 7  theme top RGB
//   row 8  R=fire(0/1, >0.5 == on) G=unused B=unused
//   row 9  R=peaks(0/1, >0.5 == on) G=falloff(0..1) B=unused A=unused
//   row 10 R=RESERVED/UNUSED G=RESERVED/UNUSED B=unused
//         (formerly alpha; main() outputs alpha 1.0, so unused. ADR-0004)
//   row 11 R=density/256 (NB bar count)  G=barGap(0..1)  B=unused
// Qt6 ShaderEffect provides the default vertex shader + qt_TexCoord0.
// NB (bar count) is DYNAMIC (density, 1..256) and rides in the control texture
// row 11 R channel as density/256.0, so the desktop window can render a dense
// spectrum while the mini keeps its 32-band feed — no free-standing uniform.

layout(location = 0) in vec2 qt_TexCoord0;
layout(binding = 1) uniform sampler2D u_tex;
layout(location = 0) out vec4 fragColor;

const float H = 12.0;
const int MAXB = 256;   // hard cap; loops break at int(nbVal())
const int NW = 24;      // wave ribbon count (ref 06 wave spirit)
float bandAt(float x) { return texture(u_tex, vec2(clamp(x,0.0,1.0), 0.5/H)).r; }
float peakAt(float x) { return texture(u_tex, vec2(clamp(x,0.0,1.0), 1.5/H)).r; }
// NB (bar count) rides in control-texture row 11 R as density/256 (set by QML).
float nbVal() { return floor(texture(u_tex, vec2(0.5, 11.5/H)).r * 256.0 + 0.5); }
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

// DENSE look: barGap is a 0..1 fraction of one bar slot. 0 = contiguous
// (immersive dense spectrum, used by the desktop window); ~0.10 = slim gaps
// (mini bar default). Rides in control-texture row 11 G (no free uniform).
float gap() { return clamp(scopeRow().g, 0.0, 0.9); }
// barWidth is the FRACTION of one bar SLOT occupied by the bar (0..1).
// lx below is already normalized per-slot via fract(x*nbVal()), so dividing
// by nbVal() here was a double-normalization bug that made bars ~1/128 wide.
float barWidth() { return clamp(1.0 - gap(), 0.02, 1.0); }
float barCenter(float bx) { return (bx + 0.5) / nbVal(); }

// FIX (v7.5): toggles decoded with > 0.5 (painted 0/1.0; old int(r*2+0.5)==1
// read 1.0 as 2 -> fire/peaks never turned on).
bool fireOn() { return fireRow().r > 0.5; }
bool peaksOn() { return peaksRow().r > 0.5; }
float falloff() { return peaksRow().g; }

// Fire palette (theme-sourced, Winamp-fluid).
// t: 0 at flame base (hottest) -> 1 at tip. Uses the active Omarchy theme's
// accent ramp (cTop = bright base, cBot = deeper tip) so fire matches the
// theme (per THEME_PALETTE.md gate). White-hot core is added in main().
vec3 fireColor(float t) {
  return mix(cTop(), cBot(), clamp(t, 0.0, 1.0));
}

// Theme gradient for a normalized height t (0 at bar bottom -> 1 at bar top).
// Uses the active Omarchy theme's accent (bottom) -> a brighter shade (top).
// themeBottom/themeTop are seeded from THEME_PALETTE.md (active Omarchy theme).
vec3 themeColor(float t) {
  if (int(ctrl().g * 2.0 + 0.5) == 1) return cust(); // custom color
  return mix(cBot(), cTop(), clamp(t*0.95+0.05, 0.0, 1.0));
}

void main() {
  vec2 uv = qt_TexCoord0;
  float x = uv.x, y = uv.y;
  vec3 col = vec3(0.0);

  // ---- Visual dispatch (3-mode, packed as 0/1/2 in ctrl().r) ----
  int visual = int(ctrl().r * 255.0 + 0.5);
  bool fire = fireOn();

  if (visual == 0) {
    // ===================== ANALYZER (Bars) =====================
    // Dynamic background: dark base with subtle theme-tinted gradient.
    float time = meta().r * 500.0;
    vec3 baseCol = mix(cBot()*0.15, cTop()*0.08, uv.y);
    float vig = 1.0 - 0.35 * length(uv - vec2(0.5, 0.5));
    col = clamp(baseCol + 0.02 * sin(uv.x * 6.0 + time * 0.01), 0.0, 1.0) * vig;
    if (peaksOn()) {
      float extraGlow = 0.0;
      for (int i = 0; i < MAXB; i++) {
        if (i >= int(nbVal())) break;
        float pk = peakAt(float(i) / max(nbVal() - 1.0, 1.0));
        extraGlow += pk * 0.015;
      }
      col += vec3(1.0) * extraGlow * 0.15;
    }

    float bx = floor(x * nbVal());
    float lx = fract(x * nbVal());
    float v = bandAt(barCenter(bx));
    if (fire) {
      // ---- Winamp-style 2D fluid/drip fire (no 3D) ----
      float t = meta().r * 6.2831;            // looping time phase (.r channel)
      float yy = 1.0 - y;                      // 0 at bottom, 1 at top
      float flick = 0.5*sin(bx*1.7 + t*1.7)
                  + 0.5*sin(bx*3.3 - t*1.1)
                  + 0.5*sin(bx*0.7 + t*0.6);
      flick /= 1.5;                            // ~ -1..1
      float flameH = clamp(v * (0.85 + 0.25*flick), 0.0, 1.0);
      if (flameH < 0.02) flameH = 0.0;
      float body = smoothstep(flameH, flameH - 0.18, yy);
      float drip = 0.14 * (0.5 + 0.5*sin(bx*2.3 - t*2.0)) * step(yy, flameH);
      body = max(body - drip, 0.0);
      float ct = clamp(yy / max(flameH, 0.001), 0.0, 1.0); // 0 base -> 1 tip
      vec3 fc = fireColor(ct);
      fc = mix(vec3(1.0, 0.95, 0.8), fc, smoothstep(0.0, 0.16, yy));
      col += fc * body;
    } else {
      // ---- Solid bars (Winamp-style, 2D, dense) ----
      float h = v * 0.96;
      float bottom = 1.0 - h;
      float insideF = step(lx, barWidth()) * step(bottom, y);
      bool inside = insideF > 0.5;
      vec3 barCol = themeColor((y - bottom) / max(h, 0.001));
      float edge = smoothstep(barWidth()*0.92, barWidth()*0.85, lx) * insideF;
      col += barCol * edge * 0.15;
      if (inside) {
        col += barCol;
        col += barCol * smoothstep(0.02, 0.0, abs(y - bottom)) * step(h, 0.99);
      }
    }
  } else if (visual == 2) {
    // ===================== WAVE (ref 06 wave spirit) =====================
    // Warm vertical gradient background + vignette, then a woven field of
    // CONTINUOUS flowing ribbons (ref 06: always-present sine lines, music
    // only flexes their amplitude, never breaks them). Audio-reactive.
    vec3  wbg = mix(cBot()*0.32, cTop()*0.64, uv.y);
    float vig = 1.0 - 0.42 * length(uv - vec2(0.5, 0.5));
    col = wbg * vig;
    // Overall loudness from mean spectrum energy -> silence = gentle, loud = big swings.
    float E = 0.0;
    for (int k = 0; k < 16; k++) E += bandAt(float(k) / 15.0);
    E /= 16.0;
    float react = smoothstep(0.0, 0.55, E);     // 0 at silence -> 1 when loud
    for (int i = 0; i < NW; i++) {
      float depth = float(i) / float(NW - 1);
      float baseY = 0.18 + depth * 0.64;
      // Continuous carrier sine = the woven line itself. ALWAYS at full amplitude
      // (added directly, never scaled to ~0) so every ribbon is a clearly visible
      // CONTINUOUS wavy line even at silence (ref 06: always-present flowing lines).
      float freq  = 4.0 + depth * 9.0;
      float phase = meta().r * (0.5 + depth * 0.7) * 6.2831 + depth * 2.5;
      float carrier = sin(uv.x * freq + phase);
      // Spectrum MODULATES the line (woven to music) but as an ADDITIVE swing on
      // top of the always-visible carrier, so it never collapses to sparse dots.
      float px = uv.x * 0.5 + depth * 0.20;
      float env = bandAt(px) + bandAt(fract(px + 0.03)) + bandAt(fract(px - 0.03));
      env /= 3.0;                                // 3-tap smooth envelope
      float yw = baseY + carrier * 0.13            // always-on line (~0.13 amplitude)
                       + env * 0.55 * react;        // extra audio swing when loud
      // Glowing core + soft halo for a luminous, woven ribbon (ref 06).
      // Wide radii so ribbons read as continuous lines (not points) at ~700px width.
      float core = smoothstep(0.045, 0.0, abs(uv.y - yw));
      float halo = smoothstep(0.140, 0.0, abs(uv.y - yw));
      vec3  rc   = mix(vec3(1.0, 0.97, 0.90), mix(cTop(), cBot()*0.5, depth), depth);
      col += rc * halo * 0.70 * (1.0 - depth * 0.45);
      col += rc * core * (2.4 - depth * 0.45);
    }
  } else {
    // ===================== OSCILLOSCOPE =====================
    int   sStyle  = int(scopeRow().r * 2.0 + 0.5);  // 0 line, 1 dot
    vec3  wbg = mix(cBot()*0.12, cTop()*0.08, uv.y);
    float vig = 1.0 - 0.35 * length(uv - vec2(0.5, 0.5));
    col = wbg * vig;
    float env = 0.0;
    for (int i = 0; i < MAXB; i++) {
      if (i >= int(nbVal())) break;
      env += bandAt(float(i) / max(nbVal() - 1.0, 1.0));
    }
    env /= max(nbVal(), 1.0);
    float w = env * 0.9;
    float ph = x * 12.0 + meta().r * 4.0;
    float wave = sin(ph) * w + 0.15 * sin(ph * 3.0 + 1.0) * w;
    float wy = 0.5 + wave * 0.45;
    float d = abs(y - wy);
    // ADR-0004: oscilloscope line width is fixed; row 10 G is reserved/unused
    // (VisualCanvasGL packs row 10 G = 0), so the former `(alphaRow().g*0.02)`
    // term was dead. Use a fixed width.
    const float OSC_LINE_W = 0.004;
    float lw = OSC_LINE_W;
    vec3 sc = themeColor(y);
    float m;
    if (sStyle == 1) {
      float dd = length(vec2((fract(x*nbVal())-0.5), d));
      m = step(dd, lw);
    } else {
      m = step(d, lw);
    }
    col = mix(col, sc, m);
  }

  fragColor = vec4(col, 1.0);
}
