#version 440
// omaviz GPU spectrum renderer — pixel-exact port of VisualCanvas.qml.
// Data texture 512x3 (NEAREST): row0 bands, row1 JS peaks, row2 wave.
// All scalars ride as uniforms (precise; no 8-bit packing).
// Coordinate convention: y DOWN, like Canvas2D.
layout(location = 0) in vec2 qt_TexCoord0;
layout(binding = 1) uniform sampler2D u_tex;
layout(location = 0) out vec4 fragColor;

// Vulkan GLSL forbids loose non-opaque uniforms: every scalar rides in
// this block, filled by name from the ShaderEffect's QML properties.
layout(std140, binding = 2) uniform buf {
  float u_pxW, u_pxH, u_nb, u_gap, u_visual;
  float u_spikes, u_splits, u_fire, u_dots, u_reflect;
  float u_art, u_mono, u_monoLight, u_sync;
  vec3 u_bot;
  vec3 u_top;
  float u_thick, u_peaks;
};

const float TEXW = 512.0;
float bandAt(float i)  { return texture(u_tex, vec2((i + 0.5) / TEXW, 0.5 / 3.0)).r; }
float peakAt(float i)  { return texture(u_tex, vec2((i + 0.5) / TEXW, 1.5 / 3.0)).r; }
float waveAt(float i)  { return texture(u_tex, vec2((clamp(i, 0.0, 127.0) + 0.5) / TEXW, 2.5 / 3.0)).r * 2.0 - 1.0; }

vec3 fireColorAt(float t) {
  t = clamp(t, 0.0, 1.0);
  if (t < 0.25) { float k = t / 0.25; return vec3(190.0 + k * 65.0, 20.0 + k * 120.0, k * 10.0) / 255.0; }
  float k2 = (t - 0.25) / 0.75; return vec3(255.0, 140.0 + k2 * 110.0, 10.0 + k2 * 190.0) / 255.0;
}
// Flat per-bar fill = Canvas fillFor(v): art forces white; mono B&W;
// fire luminous ramp; sync theme blend; else bottom-to-white-hot.
vec3 flatFill(float v) {
  if (u_art > 0.5) return vec3(1.0);
  if (u_mono > 0.5) return (u_monoLight > 0.5) ? vec3(0.0) : vec3(1.0);
  if (u_fire > 0.5) return vec3(255.0, 140.0 + v * 115.0, 60.0 + v * 40.0) / 255.0;
  vec3 top = (u_sync > 0.5) ? u_top : vec3(1.0);
  return mix(u_bot, top, v);
}
vec3 barInk(float v, float t) {
  // t = height fraction 0 base .. 1 tip (fire gradient axis).
  if (u_art > 0.5) return vec3(1.0);
  if (u_mono > 0.5) return (u_monoLight > 0.5) ? vec3(0.0) : vec3(1.0);
  if (u_fire > 0.5) return fireColorAt(t);
  return flatFill(v);
}
float sdRoundBox(vec2 p, vec2 b, float r) {
  vec2 q = abs(p) - b + r;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void main() {
  float W = u_pxW, H = u_pxH;
  vec2 px = vec2(qt_TexCoord0.x * W, qt_TexCoord0.y * H);

  // ---- Oscilloscope ----
  if (u_visual > 0.5) {
    float mid = H * 0.5, amp = H * 0.42;
    float best = 1e9;
    vec2 prev = vec2(0.0, mid - clamp(waveAt(0.0), -1.0, 1.0) * amp);
    for (int s = 1; s < 128; s++) {
      float fi = float(s);
      vec2 cur = vec2(fi / 127.0 * W, mid - clamp(waveAt(fi), -1.0, 1.0) * amp);
      vec2 pa = px - prev, ba = cur - prev;
      float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
      best = min(best, length(pa - ba * h));
      prev = cur;
    }
    float lw = clamp(u_thick, 1.0, 5.0);
    if (best < lw * 0.5) {
      vec3 col = (u_fire > 0.5) ? fireColorAt(0.7) : flatFill(0.8);
      fragColor = vec4(col, 1.0);
      return;
    }
    fragColor = vec4(0.0);
    return;
  }

  // ---- Bars ----
  float nb = clamp(u_nb, 1.0, 512.0);
  float gap = u_gap;
  float bw = (u_spikes > 0.5) ? max(1.0, W / nb) : max(2.0, (W - gap * (nb - 1.0)) / nb);
  float step_ = bw + gap;
  float fi = clamp(floor(px.x / step_), 0.0, nb - 1.0);
  float x0 = fi * step_;
  bool inBar = px.x < x0 + bw + 0.5;   // 0.5 spike-overlap seals seams
  float v = bandAt(fi);

  float areaH = (u_reflect > 0.5) ? H * 0.62 : H;
  float baseY = (u_reflect > 0.5) ? H * 0.68 : H;
  float h = v * areaH;
  float yTop = baseY - h;

  vec3 col = vec3(0.0);
  float alpha = 0.0;

  if (inBar && h > 0.0 && px.y >= yTop && px.y <= baseY) {
    float t = clamp((baseY - px.y) / max(areaH, 1e-3), 0.0, 1.0);
    if (u_splits > 0.5) {
      // 3px blocks + 1px gaps stacked from the base.
      float rel = baseY - px.y;
      if (mod(rel, 4.0) < 3.0) { col = barInk(v, t); alpha = 1.0; }
      // Spikes combo: pointed tip quad above the top segment.
      if (u_spikes > 0.5) {
        float apex = min(bw, 5.0);
        if (px.y < yTop && px.y >= yTop - apex) {
          float hw = (bw * 0.5 + 0.25) * (yTop - px.y) / max(apex, 1e-3);
          if (abs(px.x - (x0 + bw * 0.5)) <= hw) { col = barInk(v, t); alpha = 1.0; }
        }
      }
    } else if (u_spikes > 0.5) {
      float tipH = clamp(bw, 3.0, 7.0);
      col = barInk(v, t);
      if (h > tipH + 1.0) {
        if (px.y >= yTop + tipH) { alpha = 1.0; }
        else {
          float hw = (bw * 0.5 + 0.25) * (px.y - yTop) / tipH;
          if (abs(px.x - (x0 + bw * 0.5)) <= hw) alpha = 1.0;
        }
      } else {
        float hw = (bw * 0.5 + 0.25) * (px.y - yTop) / max(h, 1e-3);
        if (abs(px.x - (x0 + bw * 0.5)) <= hw) alpha = 1.0;
      }
    } else {
      // Solid rounded bar.
      float r = min(bw * 0.5, 3.0);
      vec2 c = vec2(x0 + bw * 0.5, yTop + h * 0.5);
      if (sdRoundBox(px - c, vec2(bw * 0.5, h * 0.5), r) <= 0.0) {
        col = barInk(v, t); alpha = 1.0;
      }
    }
  }

  // ---- Peak caps ----
  if (u_peaks > 0.5) {
    float pv = peakAt(fi);
    if (pv >= 0.02 && inBar) {
      float py = baseY - pv * areaH;
      float capH = (u_spikes > 0.5) ? 1.0 : 2.0;
      if (px.y >= py - 1.0 && px.y < py - 1.0 + capH) {
        if (u_art > 0.5) col = vec3(1.0);
        else if (u_mono > 0.5) col = (u_monoLight > 0.5) ? vec3(0.0) : vec3(1.0);
        else col = (u_spikes > 0.5) ? vec3(1.0, 0.914, 0.659) : vec3(1.0);
        alpha = 1.0;
      }
    }
  }

  // ---- Floor reflection (flat faded copy) ----
  if (u_reflect > 0.5 && px.y > baseY + 2.0 && inBar) {
    float mh = v * areaH * 0.5;
    if (px.y <= baseY + 2.0 + mh) {
      vec3 rc;
      if (u_art > 0.5) rc = vec3(1.0);
      else if (u_mono > 0.5) rc = (u_monoLight > 0.5) ? vec3(0.0) : vec3(1.0);
      else rc = (u_fire > 0.5) ? fireColorAt(0.12) : u_bot;
      // Under-bar blend: bars drawn above already won; mix dim copy.
      col = mix(col, rc, (1.0 - alpha) * 0.22);
      alpha = max(alpha, 0.22 * step(0.5, mh));
    }
  }

  // ---- Artwork wash (reactive glow behind white bars) ----
  if (u_art > 0.5) {
    float g0 = bandAt(max(fi - 1.0, 0.0));
    float g2 = bandAt(min(fi + 1.0, nb - 1.0));
    float gv = (g0 + v + g2) / 3.0;
    float gh = max(2.0, gv * H);
    if (px.y > H - gh) {
      vec3 wc = (u_fire > 0.5)
        ? vec3(255.0, 120.0 + gv * 120.0, 60.0) / 255.0
        : mix(u_bot, (u_sync > 0.5) ? u_top : vec3(1.0), gv);
      col = mix(col, wc, (1.0 - alpha) * 0.10);
      alpha = max(alpha, 0.10 * step(2.0, gh));
    }
  }

  // ---- Dotted backdrop (behind everything) ----
  if (alpha <= 0.0 && u_dots > 0.5) {
    vec2 gdot = mod(px - 2.0, 6.0);
    if (gdot.x < 1.0 && gdot.y < 1.0 && px.x > 1.0 && px.y > 1.0) {
      col = vec3(1.0); alpha = 0.05;
    }
  }

  fragColor = vec4(col, alpha);
}
