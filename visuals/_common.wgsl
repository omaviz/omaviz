// Shared uniform layout for every omaviz visualization.
// Include-by-concatenation: the client prepends this to each visual's WGSL.

struct Uniforms {
    // x = time seconds, y = energy 0..1, z = beat 0..1, w = n_bands
    params: vec4<f32>,
    // xy = viewport pixels, z = sensitivity, w = unused
    view: vec4<f32>,
    low: vec4<f32>,
    high: vec4<f32>,
    bg: vec4<f32>,
};

@group(0) @binding(0) var<uniform> U: Uniforms;
@group(0) @binding(1) var<storage, read> bands: array<f32>;

@vertex
fn vs_main(@builtin(vertex_index) i: u32) -> @builtin(position) vec4<f32> {
    // Fullscreen triangle, no vertex buffer.
    var p = array<vec2<f32>, 3>(
        vec2<f32>(-1.0, -1.0),
        vec2<f32>( 3.0, -1.0),
        vec2<f32>(-1.0,  3.0),
    );
    return vec4<f32>(p[i], 0.0, 1.0);
}

fn n_bands() -> u32 {
    return max(u32(U.params.w), 1u);
}

// Linearly interpolated band lookup for smooth horizontal gradients.
fn band_lerp(x: f32) -> f32 {
    let n = n_bands();
    let f = clamp(x, 0.0, 0.9999) * f32(n);
    let i0 = u32(f);
    let i1 = min(i0 + 1u, n - 1u);
    let t = f - f32(i0);
    return mix(bands[i0], bands[i1], t) * U.view.z;
}

fn palette(t: f32) -> vec3<f32> {
    return mix(U.low.rgb, U.high.rgb, clamp(t, 0.0, 1.0));
}
