// Equalizer WGSL — stacked bars driven by spectrum uniform buffer.
// Runs in the detached desktop window via omaviz desktop binary.

@group(0) @binding(0) var<uniform> bands: array<f32, 64>;
@group(0) @binding(1) var<uniform> count: u32;
@group(0) @binding(2) var<uniform> sensitivity: f32;
@group(0) @binding(3) var<uniform> color_scheme: u32;

@vertex
fn vs(@builtin(vertex_index) vi: u32) -> @builtin(position) vec4<f32> {
    let idx = u32(vi) % count;
    let bar_w = 1.0 / f32(count);
    let x = (f32(idx) + 0.5) * bar_w * 2.0 - 1.0;
    let h = clamp(bands[idx] * sensitivity * 0.8, 0.0, 1.0);
    let y = -h * 0.8;
    return vec4<f32>(x, y, 0.0, 1.0);
}

@fragment
fn fs(@builtin(position) pos: vec4<f32>) -> @location(0) vec4<f32> {
    let col = select(
        vec3<f32>(1.0, 0.6, 0.2),
        select(vec3<f32>(0.2, 0.6, 1.0), vec3<f32>(0.9, 0.9, 0.95), color_scheme == 2u),
        color_scheme == 1u
    );
    return vec4<f32>(col, 1.0);
}
