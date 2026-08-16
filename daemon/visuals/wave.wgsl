// "wave" — mirrored spectrum ribbon with bloom, tuned for fullscreen.

@fragment
fn fs_main(@builtin(position) frag: vec4<f32>) -> @location(0) vec4<f32> {
    let uv = vec2<f32>(frag.x / U.view.x, 1.0 - frag.y / U.view.y);
    let centered = uv.y - 0.5;

    let amp = band_lerp(uv.x);
    let half_h = 0.02 + amp * 0.42;

    let d = abs(centered) - half_h;
    var col = U.bg.rgb;

    // Core ribbon.
    let core = 1.0 - smoothstep(0.0, 0.006, d);
    // Outer bloom, driven by beat.
    let bloom = exp(-max(d, 0.0) * (34.0 - 14.0 * U.params.z));

    let tint = palette(uv.x * 0.65 + amp * 0.35);
    col = col + tint * (core + bloom * (0.30 + 0.45 * U.params.y));

    // Subtle horizontal scanline shimmer, cheap.
    col = col * (0.96 + 0.04 * sin(uv.y * 420.0 + U.params.x * 2.0));

    return vec4<f32>(col, 1.0);
}
