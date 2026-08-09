// Shared uniform layout for every omaviz visualization.
// The client prepends this to each visual's WGSL, so all shaders see the same
// bindings and helpers and stay hot-swappable.

struct Uniforms {
    // x = time seconds, y = energy 0..1, z = beat 0..1, w = band count
    params: vec4<f32>,
    // x = width px, y = height px, z = sensitivity, w = light theme (0/1)
    view: vec4<f32>,
    low: vec4<f32>,
    high: vec4<f32>,
    bg: vec4<f32>,
    // Per-visual knobs, in the order the visual's .toml declares them.
    knobs: vec4<f32>,
    knobs2: vec4<f32>,
};

@group(0) @binding(0) var<uniform> U: Uniforms;
@group(0) @binding(1) var<storage, read> bands: array<f32>;
// Per-band peak line (winamp-style hold), written by the host each frame so
// shaders that want a held cap can sample it at any x.
@group(0) @binding(2) var<storage, read> peaks: array<f32>;

// Knob accessor: k(0)..k(7) map to the declared parameters.
fn k(i: i32) -> f32 {
    switch i {
        case 0: { return U.knobs.x; }
        case 1: { return U.knobs.y; }
        case 2: { return U.knobs.z; }
        case 3: { return U.knobs.w; }
        case 4: { return U.knobs2.x; }
        case 5: { return U.knobs2.y; }
        case 6: { return U.knobs2.z; }
        default: { return U.knobs2.w; }
    }
}

fn palette(t: f32) -> vec3<f32> {
    return mix(U.low.rgb, U.high.rgb, clamp(t, 0.0, 1.0));
}

// Number of spectrum bands (the WGSL `array<f32>` has no .len(), so the host
// passes it in U.params.w). Kept as a helper so visuals can call n_bands().
fn n_bands() -> u32 {
    return max(u32(U.params.w), 1u);
}

// Band value at normalised x, with linear interpolation between bins.
fn band_at(x: f32) -> f32 {
    let n = U.params.w;
    let f = clamp(x, 0.0, 0.9999) * n;
    let i = i32(floor(f));
    let j = min(i + 1, i32(n) - 1);
    return mix(bands[i], bands[j], fract(f));
}

// Peak-hold line at normalised x (held cap, falls slowly), same lookup as bands.
fn peak_at(x: f32) -> f32 {
    let n = U.params.w;
    let f = clamp(x, 0.0, 0.9999) * n;
    let i = i32(floor(f));
    let j = min(i + 1, i32(n) - 1);
    return mix(peaks[i], peaks[j], fract(f));
}

@vertex
fn vs_main(@builtin(vertex_index) vi: u32) -> @builtin(position) vec4<f32> {
    // Fullscreen triangle.
    var p = array<vec2<f32>, 3>(
        vec2<f32>(-1.0, -3.0),
        vec2<f32>(-1.0,  1.0),
        vec2<f32>( 3.0,  1.0),
    );
    return vec4<f32>(p[vi], 0.0, 1.0);
}
