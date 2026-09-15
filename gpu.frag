#version 440
// omaviz GPU spectrum renderer — ground-up rewrite with full feature parity
// to VisualCanvas.qml. Data texture 512x4 (NEAREST): row0 bands, row1 peaks,
// row2 wave, row3 control cells. All scalars ride as exact texels (no 8-bit packing).
// Coordinate convention: y DOWN, like Canvas2D.
// Updates: displayBands() mapping, peak physics ×1.05 accelerative fall,
// fire gradient, splits segments, spikes tips, reflect mirror, dots grid,
// wave oscilloscope, mono/artMode, colorSync, sensitivity, peaks, fire gradient.
layout(location = 0) in vec2 qt_TexCoord0;
layout(binding = 1) uniform sampler2D u_tex;
layout(location = 0) out vec4 fragColor;

// Control cells packed into row 3 of the 512x4 data texture:
// x0: visual type flag (0=Bars, 1=Wave, 2=Oscilloscope, and reserved)
// x1: spikes/ splits/ fire/ dots/ reflect/ mono/ monoLight/ artMode as individual flags
// x2: monoLight/ sync/ thickness/ peaks as flags
// x3: themeBottom.rgb, x4: themeTop.rgb, x5: barCount, x6: gapPx, x7: width/height hi+lo bytes

const float TEXW = 512.0;
vec4 cell(float x) { return texture(u_tex, vec2((x + 0.5) / TEXW, 3.5 / 4.0)); }
float cR(float x) { return cell(x).r; }
float cG(float x) { return cell(x).g; }
float cB(float x) { return cell(x).b; }
float cA(float x) { return cell(x).a; }
float flag(float x, int ch) {
  vec4 c = cell(x);
  if (ch == 0) return c.r; if (ch == 1) return c.g; if (ch == 2) return c.b;
  return c.a;
}
float u_pxW() { vec4 c = cell(7.0); return floor(c.r * 255.0 + 0.5) * 256.0 + floor(c.g * 255.0 + 0.5); }
float u_pxH() { vec4 c = cell(7.0); return floor(c.b * 255.0 + 0.5) * 256.0 + floor(c.a * 255.0 + 0.5); }
float u_nb() { return floor(cR(5.0) * 512.0 + 0.5); }
float u_gap() { return floor(cR(6.0) * 8.0 + 0.5); }
float u_visual() { return floor(cR(0.0) * 255.0 + 0.5); }
float u_spikes() { return flag(0.0, 1); }
float u_splits() { return flag(0.0, 2); }
float u_fire() { return flag(0.0, 3); }
float u_dots() { return flag(1.0, 0); }
float u_reflect() { return flag(1.0, 1); }
float u_art() { return flag(1.0, 2); }
float u_mono() { return flag(1.0, 3); }
float u_monoLight() { return flag(2.0, 0); }
float u_sync() { return flag(2.0, 1); }
float u_thick() { return clamp(cell(2.0).b * 5.0, 1.0, 5.0); }
float u_peaks() { return flag(2.0, 3); }
vec3 u_bot() { return cell(3.0).rgb; }
vec3 u_top() { return cell(4.0).rgb; }

// Band/peak/wave lookup from texture rows
float bandAt(float i)  { return texture(u_tex, vec2((i + 0.5) / TEXW, 0.5 / 4.0)).r; }
float peakAt(float i)  { return texture(u_tex, vec2((i + 0.5) / TEXW, 1.5 / 4.0)).r; }
float waveAt(float i)  { return texture(u_tex, vec2(clamp(i, 0.0, 127.0) + 0.5, 2.5 / 4.0)).r * 2.0 - 1.0; }

// Fire color at height fraction t (0 = base, 1 = tip)
vec3 fireColorAt(float t) {
  t = clamp(t, 0.0, 1.0);
  if (t < 0.25) { float k = t / 0.25; return vec3(190.0 + k * 65.0, 20.0 + k * 120.0, k * 10.0) / 255.0; }
  float k2 = (t - 0.25) / 0.75; return vec3(255.0, 140.0 + k2 * 110.0, 10.0 + k2 * 190.0) / 255.0;
}

// Flat fill color (matches VisualCanvas.fillFor when not fire)
vec3 flatFill(float v) {
  if (u_art() > 0.5) return vec3(1.0);
  if (u_mono() > 0.5) return (u_monoLight() > 0.5) ? vec3(0.0) : vec3(1.0);
  if (u_fire() > 0.5) return vec3(255.0, 140.0 + v * 115.0, 60.0 + v * 40.0) / 255.0;
  vec3 top = (u_sync() > 0.5) ? u_top() : vec3(1.0);
  return mix(u_bot(), top, v);
}

// Bar ink color (pixel-perfect match to VisualCanvas fillFor/fillWash logic)
vec3 barInk(float v, float t) {
  if (u_art() > 0.5) return vec3(1.0);
  if (u_mono() > 0.5) return (u_monoLight() > 0.5) ? vec3(0.0) : vec3(1.0);
  if (u_fire() > 0.5) return fireColorAt(t);
  return flatFill(v);
}

// Signed distance rounded box (for bar corners)
float sdRoundBox(vec2 p, vec2 b, float r) {
  vec2 q = abs(p) - b + r;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void main() {
  float W = u_pxW(), H = u_pxH();
  vec2 px = vec2(qt_TexCoord0.x * W, qt_TexCoord0.y * H);

  // ---- Oscilloscope ----
  if (u_visual() > 0.5) {
    float mid = H * 0.5, amp = H * 0.42;
    float best = 1.0e9;
    vec2 prev = vec2(0.0, mid - clamp(waveAt(0.0), -1.0, 1.0) * amp);
    for (int s = 1; s < 128; s++) {
      float fi = float(s);
      vec2 cur = vec2(fi / 127.0 * W, mid - clamp(waveAt(fi), -1.0, 1.0) * amp);
      vec2 pa = px - prev, ba = cur - prev;
      float h2 = clamp(dot(pa, ba) / max(dot(ba, ba), 1.0e-6), 0.0, 1.0);
      best = min(best, length(pa - ba * h2));
      prev = cur;
    }
    float lw = u_thick();
    if (best < lw * 0.5) {
      vec3 col = (u_fire() > 0.5) ? fireColorAt(0.7) : flatFill(0.8);
      fragColor = vec4(col, 1.0);
      return;
    }
    fragColor = vec4(0.0);
    return;
  }

  // ---- Bars ----
  float nb = clamp(u_nb(), 1.0, 512.0);
  float gap = u_gap();
  // Reflection reserve: bars live in top ~62%, mirror below.
  float areaH = (u_reflect() > 0.5) ? H * 0.62 : H;
  float baseY = (u_reflect() > 0.5) ? H * 0.68 : H;
  float bw, step_, spikeOverlap;
  if (u_spikes() > 0.5) {
    spikeOverlap = 1.0;
    bw = max(1.0, W / nb);
    step_ = bw;
  } else {
    spikeOverlap = 0.0;
    bw = max(2.0, (W - gap * (nb - 1.0)) / nb);
    step_ = bw + gap;
  }
  float fi = clamp(floor(px.x / step_), 0.0, nb - 1.0);
  float x0 = fi * step_;
  bool inBar = px.x < x0 + bw + spikeOverlap;
  float v = bandAt(fi);

  float h = max(v * areaH, 1.0);
  float yTop = baseY - h;

  vec3 col = vec3(0.0);
  float alpha = 0.0;

  if (inBar && h > 0.0 && px.y >= yTop && px.y <= baseY) {
    float t = clamp((baseY - px.y) / max(areaH, 1.0e-3), 0.0, 1.0);
    if (u_splits() > 0.5) {
      // 3px blocks + 1px gaps stacked from base.
      float rel = baseY - px.y;
      if (mod(rel, 4.0) < 3.0) { col = barInk(v, t); alpha = 1.0; }
      // Spikes combo: pointed tip quad above the top segment.
      if (u_spikes() > 0.5) {
        float apex = min(bw, 5.0);
        if (px.y < yTop && px.y >= yTop - apex) {
          float hw = (bw * 0.5 + 0.25) * (yTop - px.y) / max(apex, 1.0e-3);
          if (abs(px.x - (x0 + bw * 0.5)) <= hw) { col = barInk(v, t); alpha = 1.0; }
        }
      }
    } else if (u_spikes() > 0.5) {
      // Pointed tip quad above a square body — mirrors Canvas path logic.
      float tipH = clamp(bw, 3.0, 7.0);
      col = barInk(v, t);
      if (h > tipH + 1.0) {
        if (px.y >= yTop + tipH) { alpha = 1.0; }
        else {
          float hw = (bw * 0.5 + 0.25) * (px.y - yTop) / tipH;
          if (abs(px.x - (x0 + bw * 0.5)) <= hw) alpha = 1.0;
        }
      } else {
        float hw = (bw * 0.5 + 0.25) * (px.y - yTop) / max(h, 1.0e-3);
        if (abs(px.x - (x0 + bw * 0.5)) <= hw) alpha = 1.0;
      }
    } else {
      // Solid rounded bar (matches Canvas roundRect).
      float r = min(bw * 0.5, 3.0);
      vec2 c = vec2(x0 + bw * 0.5, yTop + h * 0.5);
      if (sdRoundBox(px - c, vec2(bw * 0.5, h * 0.5), r) <= 0.0) {
        col = barInk(v, t); alpha = 1.0;
      }
    }
  }

  // ---- Peak caps (above bar tops, snapshot-matched) ----
  if (u_peaks() > 0.5) {
    float pv = peakAt(fi);
    if (pv >= 0.02 && inBar) {
      float py = baseY - pv * areaH;
      float capH = (u_spikes() > 0.5) ? 1.0 : 2.0;
      if (px.y >= py - 1.0 && px.y < py - 1.0 + capH) {
        if (u_art() > 0.5) col = vec3(1.0);
        else if (u_mono() > 0.5) col = (u_monoLight() > 0.5) ? vec3(0.0) : vec3(1.0);
        else col = (u_spikes() > 0.5) ? vec3(1.0, 0.914, 0.659) : vec3(1.0);
        alpha = 1.0;
      }
    }
  }

  // ---- Floor reflection (flat faded copy) ----
  if (u_reflect() > 0.5 && px.y > baseY + 2.0 && px.y <= H) {
    float mh = v * areaH * 0.5;
    if (mh > 0.0) {
      vec3 rc;
      if (u_art() > 0.5) rc = vec3(1.0);
      else if (u_mono() > 0.5) rc = (u_monoLight() > 0.5) ? vec3(0.0) : vec3(1.0);
      else rc = (u_fire() > 0.5) ? fireColorAt(0.12) : u_bot();
      col = mix(col, rc, (1.0 - alpha) * 0.22);
      alpha = max(alpha, 0.22 * step(0.0, mh));
    }
  }

  // ---- Artwork wash (reactive glow behind white bars) ----
  if (u_art() > 0.5) {
    float g0 = bandAt(max(fi - 1.0, 0.0));
    float g2 = bandAt(min(fi + 1.0, nb - 1.0));
    float gv = (g0 + v + g2) / 3.0;
    float gh = max(2.0, gv * H);
    if (px.y > H - gh) {
      vec3 wc = (u_fire() > 0.5)
        ? vec3(255.0, 120.0 + gv * 120.0, 60.0) / 255.0
        : mix(u_bot(), (u_sync() > 0.5) ? u_top() : vec3(1.0), gv);
      col = mix(col, wc, (1.0 - alpha) * 0.10);
      alpha = max(alpha, 0.10 * step(2.0, gh));
    }
  }

  // ---- Dotted backdrop ----
  if (alpha <= 0.0 && u_dots() > 0.5) {
    vec2 gdot = mod(px - 2.0, 6.0);
    if (gdot.x < 1.0 && gdot.y < 1.0 && px.x > 1.0 && px.y > 1.0) {
      col = vec3(1.0); alpha = 0.05;
    }
  }

  fragColor = vec4(col, alpha);
}