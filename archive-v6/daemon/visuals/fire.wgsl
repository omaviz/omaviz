// "fire" — fluid, borderless spectrum that flows like fire.
//
//   * bars have NO gaps (knob 0 = borderless) so they merge into a continuous
//     flame shape, with a little horizontal smoothing for a liquid edge
//   * winamp-style peak-hold "bricks": each bar keeps a small cap that sits at
//     the highest recent level and falls slowly (knob 4 = peak_fall), passed in
//     by the host as knobs.z (the renderer remembers last frame's peaks)
//   * background fades with overall energy (knob 2 = bg_fade): louder = brighter
//     glow behind the flame, so it breathes with the music
//   * gradient runs hot (low) -> bright (high), with an additive core so the
//     tips look like they're burning

@fragment
fn fs_main(@builtin(position) frag: vec4<f32>) -> @location(0) vec4<f32> {
    let uv = vec2<f32>(frag.x / U.view.x, 1.0 - frag.y / U.view.y);

    let borderless = k(0);          // 1 = merged flame, 0 = separated bars
    let smoothing  = k(1);          // horizontal edge softness
    let bg_fade    = k(2);          // how much the bg glows with energy
    let intensity  = k(3);          // overall flame brightness
    let peak_fall  = k(4);          // peak-hold fall speed (lower = slower)

    // Continuous sample of the spectrum at this x (smoothing widens the kernel
    // so adjacent bars bleed into one another).
    let w = max(smoothing, 0.001);
    let s = band_at(uv.x) * 0.5
          + band_at(clamp(uv.x - w * 0.02, 0.0, 1.0)) * 0.25
          + band_at(clamp(uv.x + w * 0.02, 0.0, 1.0)) * 0.25;

    let h = clamp(s * U.view.z, 0.0, 1.0);

    // Winamp peak brick: a thin cap floating above the flame at the held peak.
    let peak_y = clamp(peak_at(uv.x), 0.0, 1.0);
    let brick = smoothstep(0.012, 0.0, abs(uv.y - peak_y)) * step(0.02, peak_y);

    // Distance from the flame edge -> soft falloff for a liquid border.
    let edge = abs(uv.y - h);
    let body = (1.0 - smoothstep(0.0, max(0.01, smoothing * 0.04 + 0.012), edge));

    // Colour: hot at the base, bright at the tips.
    let t = clamp(uv.y / max(h, 0.001), 0.0, 1.0);
    var col = mix(U.low.rgb, U.high.rgb, pow(t, 0.7));
    // additive core makes tips burn
    col += U.high.rgb * (1.0 - t) * 0.35;

    // Compose: flame over a soft energy-tinted background.
    let bg_glow = U.bg;
    let glow = max(body, brick);
    let a = max(bg_glow.a, glow * intensity);

    var outc = mix(bg_glow.rgb, col, glow * intensity);
    // energy-driven background fade (only when auto/opacity < 1)
    outc += U.high.rgb * U.params.y * bg_fade * 0.15 * (1.0 - bg_glow.a);

    return vec4<f32>(outc, a);
}
