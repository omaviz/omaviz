#version 440
layout(location=0) in vec2 position;
layout(location=1) in vec4 primitive; // identity, history row, strip/cap kind, reserved
layout(location=2) in vec3 seed;
layout(location=0) out vec4 tint;
layout(location=1) out vec2 local;
layout(location=2) out vec4 shape; // mode, focus/core ratio, cap kind, reserved
layout(std140,binding=0) uniform buf {
    mat4 matrix;
    vec4 surface; // opacity, width, height, physical pixel size
    vec4 scene; // integrated motion, energy, onset, mode
    vec4 layoutInfo; // element count, history rows, compact, reserved
    vec4 flags; // mono, middle color, Original palette, reserved
    vec4 bottomColor;
    vec4 middleColor;
    vec4 topColor;
    vec4 levels[6];
    vec4 history[160]; // smoothed spectral drive, waveform, reserved, reserved
} u;
const float PI=3.141592653589793;
float band(int i) { vec4 v=u.levels[i/4];return v[i%4]; }
vec4 palette(float t) {
    if(u.flags.z>0.5) {
        if(u.scene.w<0.5) return primitive.x<0.5?vec4(1.0,0.65,0.36,1.0):vec4(0.78,0.79,0.84,1.0);
        if(u.scene.w<1.5) return mix(vec4(0.51,0.54,0.62,1),vec4(0.83,0.84,0.88,1),t);
        return mix(vec4(0.83,0.86,0.98,1),vec4(1),t);
    }
    return u.flags.y>0.5?(t<0.5?mix(u.bottomColor,u.middleColor,t*2):mix(u.middleColor,u.topColor,(t-0.5)*2))
                        :mix(u.bottomColor,u.topColor,t);
}
void main() {
    vec2 corner=position/u.surface.yz*2.0-1.0;
    float id=primitive.x,time=u.scene.x,energy=u.scene.y,pulse=u.scene.z;
    float size=min(u.surface.y,u.surface.z),compact=u.layoutInfo.z;
    float count=u.layoutInfo.x,level=band(int(id)%24);
    vec2 center=u.surface.yz*0.5,p=center;
    tint=palette(id/max(1.0,count-1.0));local=corner;shape=vec4(u.scene.w,0,primitive.z,0);
    float presence=smoothstep(0.0,0.025,energy);
    if(u.scene.w<0.5) {
        float radius=size*0.43*(0.19+0.81*(id+1.0)/count);
        // Outer arcs travel in a loose group; inner arcs have their own pace.
        float speed=id<3.0?(1.3+id*0.23):1.45+id*0.028;
        float direction=mod(id,5.0)<0.5?-1.0:1.0;
        float start=time*speed*direction+(id<3.0?id*1.6:0.12*id+0.20*sin(time*0.4+id));
        float articulation=0.5+0.5*sin(time*(0.85+id*0.063)+id*2.13);
        float sweep=0.18+1.6*(0.35*energy+0.65*level)*(0.40+0.75*articulation);
        float stroke=max(u.surface.w*0.8,size*(compact>0.5?0.032:0.013));
        float extent=stroke*0.5+u.surface.w;
        float t=(corner.x+1.0)*0.5;
        float angle=start+sweep*(primitive.z>0.5?(primitive.z<1.5?0.0:1.0):t);
        vec2 normal=vec2(cos(angle),sin(angle)),tangent=vec2(-normal.y,normal.x);
        p=center+normal*radius;
        if(primitive.z<0.5) p+=normal*corner.y*extent;
        else p+=(tangent*corner.x+normal*corner.y)*extent;
        shape.y=stroke*0.5/extent;
        tint.a*=u.flags.z>0.5&&id<0.5?presence*(0.70+0.30*energy):presence*(0.20+0.80*level)*(0.35+0.65*articulation);
    } else if(u.scene.w<1.5) {
        float x=id/max(1.0,count-1.0),row=primitive.y;
        float depth=row/max(1.0,u.layoutInfo.y-1.0);
        float column=x*19.0;
        int lo=int(column),hi=min(lo+1,19),r=int(row)*20;
        vec2 drive=mix(u.history[r+lo].xy,u.history[r+hi].xy,fract(column));
        float field=min(u.surface.z,u.surface.y*0.95);
        float carrier=sin(x*PI*2.0*1.15-time*1.25-depth*1.7)
                       +0.32*sin(x*PI*4.5+time*0.8-depth);
        float amplitude=0.25+0.75*energy;
        float y=u.surface.z*0.5+field*(0.15-depth*0.18
                      -(carrier*0.115+drive.y*0.16+(drive.x-energy)*0.16)*amplitude);
        y+=field*energy*(0.055*sin(id*2.4+time*1.9-depth*2.3)
                          +0.035*sin(id*1.1-time*1.6+depth*0.9));
        float stagger=sin(id*2.1+row*0.9+time*0.7)*u.surface.y*0.008*energy;
        float side=min(u.surface.y/count*0.88,field*(compact>0.5?0.14:0.095))*(1.0-depth*0.22);
        p=vec2(u.surface.y*0.5+(x-0.5)*u.surface.y*0.92*(1.0-depth*0.12)+stagger,y)+corner*side*0.5;
        shape.y=2.0*u.surface.w/max(side,1.0);
        tint=palette(x);tint.a*=presence*(0.38+0.62*drive.x)*(1.0-depth*0.83)
                  *(0.55+0.45*(0.5+0.5*sin(id*2.0+row*1.7+time*1.9)));
    } else {
        float angle=time*0.43;
        vec3 q=vec3(seed.x*cos(angle)+seed.z*sin(angle),seed.y,-seed.x*sin(angle)+seed.z*cos(angle));
        float depth=(q.z+1.0)*0.5;
        float projection=1.0/(1.20+q.z*0.24);
        vec2 drift=vec2(sin(time*0.67+id*1.73),cos(time*0.54+id*2.31))*0.055;
        vec2 offset=q.xy*projection+drift;
        offset*=min(1.0,0.84/max(length(offset),0.001));
        p=center+offset*size*(0.48+energy*0.02);
        float focus=abs(depth-0.30)*1.7;
        float radius=size*(compact>0.5?0.047:0.038)*(0.65+1.25*depth);
        float blur=0.025+focus*0.90;
        float extent=radius*(1.0+blur);
        p=clamp(p,vec2(extent),u.surface.yz-vec2(extent));
        p+=corner*extent;
        local=corner*(1.0+blur);shape.y=blur;
        shape.zw=vec2(cos(id*2.39+time*0.3),sin(id*2.39+time*0.3));
        float glint=pow(0.5+0.5*sin(time*(1.3+mod(id,5.0)*0.12)+id*2.39),4.0);
        float excitation=0.67*energy+0.33*level;
        tint.a*=presence*(0.36+0.64*excitation)*(0.42+glint+0.20*pulse)*(0.72+0.28*(1.0-depth));
    }
    tint.a*=u.surface.x;
    gl_Position=u.matrix*vec4(p,0,1);
}
