#version 440
layout(location = 0) in vec2 position;
layout(location = 1) in vec3 shape;
layout(location = 2) in vec4 color;
layout(location = 0) out vec4 vertexColor;
layout(std140, binding = 0) uniform buf {
    mat4 matrix;
    float opacity;
    float width;
    float height;
    float phase;
    float energy;
    float pixel;
    float stepX;
    float pulse;
    vec4 levels[2];
} u;
vec2 pointAt(float x) {
    float layer=shape.x;
    float center=.28+.085*layer;
    int sheet=int(layer);
    float amplitude=u.levels[sheet/4][sheet%4];
    const float widths[6]=float[6](.22,.13,.19,.12,.17,.10);
    const float frequencies[6]=float[6](9.0,13.5,10.5,17.0,12.0,19.5);
    float spread=widths[sheet]+.05*amplitude+.02*u.pulse;
    float z=(x-center)/spread;
    float phase=layer*.83+(u.levels[1].z>.5?u.phase*(1.8+.27*layer):.8*amplitude+.35*u.pulse);
    float y=sin(x*3.14159265)*exp(-z*z*.65)*(.24+.76*abs(sin(x*frequencies[sheet]-phase)))
        *u.height*.47*amplitude*(1.0-.045*layer);
    if(shape.y<.5)y=-y;else if(shape.y<1.5)y=0;
    return vec2(x*u.width,u.height*.5+y);
}
vec2 safeNormal(vec2 p) { float len=length(p);return len>.000001?p/len:vec2(0); }
void main() {
    float x=position.x/u.width;
    vec2 p=pointAt(x);
    if(shape.z!=0) {
        vec2 before=p-pointAt(max(0.0,x-u.stepX));
        vec2 after=pointAt(min(1.0,x+u.stepX))-p;
        if(x<u.stepX*.5)before=after;
        if(x>1.0-u.stepX*.5)after=before;
        float segment=min(length(before),length(after));
        before=safeNormal(before);after=safeNormal(after);
        vec2 n0=vec2(-before.y,before.x),n1=vec2(-after.y,after.x);
        vec2 normal=safeNormal(n0+n1);normal/=max(.5,dot(normal,n1));
        float curvature=length(n1-n0);
        float radius=curvature>.001?segment/curvature:100000.0;
        float halfWidth=(shape.y<.5?.45:.4)*u.pixel;
        float offset=min(abs(shape.z),max(halfWidth,radius*.7));
        p+=normal*offset*sign(shape.z);
    }
    gl_Position=u.matrix*vec4(p,0,1);
    vertexColor=color*u.opacity;
}
