// Wave WGSL — smooth sine-wave bars with brightness control.

@group(0) @binding(0) var<uniform> bands: array<f32, 64>;
@group(0) @binding(1) var<uniform> count: u32;
@group(0) @binding(2) var<uniform> amplitude: f32;
@group(0) @binding(3) var<uniform> brightness: f32;

@vertex
fn vs(@builtin(vertex_index) vi: u32) -> @builtin(position) vec4<f32> {
    let idx = u32(vi) % count;
    let bar_w = 1.0 / f32(count);
    let x = (f32(idx) + 0.5) * bar_w * 2.0 - 1.0;
    let h = clamp(bands[idx] * amplitude * 0.8, 0.0, 1.0);
    let y = -h * 0.8;
    return vec4<f32>(x, y, 0.0, 1.0);
}

@fragment
fn fs(@builtin(position) pos: vec4<f32>) -> @location(0) vec4<f32> {
    let col = vec3<f32>(0.3, 0.7, 1.0) * brightness;
    return vec4<f32>(col, 1.0);
}
