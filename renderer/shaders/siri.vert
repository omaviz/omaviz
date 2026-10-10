#version 440
layout(location = 0) in vec2 position;
layout(location = 1) in vec3 shape; // lobe index, antialias offset in device pixels, unused
layout(location = 2) in vec4 color;
layout(location = 0) out vec4 vertexColor;
layout(std140, binding = 0) uniform buf {
    mat4 matrix;
    float opacity;
    float width;
    float height;
    float pixel;
    vec4 lobes[6]; // center, radius, height, opacity
    vec4 options; // CPU comparison path
} u;
void main() {
    vec4 lobe=u.lobes[int(shape.x)];
    vec2 p=position;
    if(u.options.x<.5) {
        p.x=(lobe.x+(2.0*position.x/u.width-1.0)*lobe.y)*u.width;
        p.y=u.height*(.5+(2.0*position.y/u.height-1.0)*lobe.z)+shape.y*u.pixel;
    }
    gl_Position=u.matrix*vec4(p,0.0,1.0);
    vertexColor=color*(u.opacity*lobe.w);
}
