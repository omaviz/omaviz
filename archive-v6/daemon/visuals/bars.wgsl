// "bars" — classic spectrum bars with rounded caps and beat glow.

@fragment
fn fs_main(@builtin(position) frag: vec4<f32>) -> @location(0) vec4<f32> {
    let uv = vec2<f32>(frag.x / U.view.x, 1.0 - frag.y / U.view.y);

    let n = n_bands();
    let gap = 0.18;
    let slot = 1.0 / f32(n);
    let idx = min(u32(uv.x / slot), n - 1u);
    let local = (uv.x - f32(idx) * slot) / slot;

    var col = U.bg.rgb;

    // Inside the bar body (excluding the gap between slots).
    if (local > gap * 0.5 && local < 1.0 - gap * 0.5) {
        let h = clamp(bands[idx] * U.view.z, 0.0, 1.0);
        if (uv.y < h) {
            // low colour at the base, high colour toward the cap
            let c = palette(uv.y / max(h, 0.001));
            // brighten toward the cap
            let cap = smoothstep(h - 0.02, h, uv.y);
            col = c + cap * 0.45;
        } else {
            // soft glow just above the cap, pulsed by beat
            let d = uv.y - h;
            let glow = exp(-d * 55.0) * (0.20 + 0.55 * U.params.z);
            col = col + palette(1.0) * glow;
        }
    }

    return vec4<f32>(col, 1.0);
}
