#version 440
layout(location = 0) in vec2 position;
layout(location = 1) in vec2 shape; // layer, signed ribbon offset
layout(location = 2) in vec3 previousBasis;
layout(location = 3) in vec3 basis;
layout(location = 4) in vec3 nextBasis;
layout(location = 5) in vec4 color;
layout(location = 0) out vec4 vertexColor;
layout(std140, binding = 0) uniform buf {
    mat4 matrix;
    float opacity;
    float width;
    float height;
    float gain;
    float count;
    vec4 vibration[56];
    vec4 coefficients[16];
} u;
vec2 pointAt(int index, vec3 b) {
    vec3 c = u.coefficients[int(shape.x)].xyz;
    float wave = u.vibration[index/4][index%4];
    float displacement = c.x*b.x + c.y*b.y + wave*c.z*b.z;
    float y = .5 + .46*tanh(u.gain*displacement/.46);
    return vec2(float(index)*u.width/(u.count-1.0),y*u.height);
}
void main() {
    int index = int(floor(position.x/u.width*(u.count-1.0)+.5));
    vec2 p = pointAt(index,basis);
    vec2 delta = pointAt(min(index+1,int(u.count)-1),nextBasis)
               - pointAt(max(index-1,0),previousBasis);
    float len = length(delta);
    vec2 normal = len > .0001 ? vec2(-delta.y,delta.x)/len : vec2(0.0,1.0);
    gl_Position = u.matrix*vec4(p+normal*shape.y,0.0,1.0);
    vertexColor = color*u.opacity;
}
