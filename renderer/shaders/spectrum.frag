#version 440
layout(location=0) in vec4 vertexColor;
layout(location=1) in vec2 flameUv;
layout(location=0) out vec4 fragColor;
layout(std140,binding=0) uniform buf {
    mat4 matrix;
    vec4 metrics;
    vec4 geometry;
    vec4 flags;
    vec4 bottomColor;
    vec4 middleColor;
    vec4 topColor;
    vec4 capColor;
    vec4 reflectionColor;
    vec4 flameInfo;
    vec4 bands[512];
} u;
float hash(vec2 p) {
    vec3 q=fract(vec3(p.xyx)*vec3(0.1031,0.1030,0.0973));
    q+=dot(q,q.yzx+33.33);return fract((q.x+q.y)*q.z);
}
float noise(vec2 p) {
    vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);
    return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);
}
float turbulence(vec2 p) {
    return 0.55*noise(p)+0.28*noise(p*2.03+7.1)+0.12*noise(p*4.09+19.3)+0.05*noise(p*8.17);
}
float band(int index) {
    int i=clamp(index,0,int(u.flameInfo.y)-1);
    vec4 v=u.bands[i/2];return i%2==0?v.x:v.z;
}
float fuelAt(float x) {
    float b=clamp(x,0.0,1.0)*max(1.0,u.flameInfo.y-1.0);
    int i=int(floor(b));float f=smoothstep(0.0,1.0,fract(b));
    // Adjacent frequency bins feed a continuous fire bed rather than needles.
    return mix((band(i-1)+2.0*band(i)+band(i+1))*0.25,
               (band(i)+2.0*band(i+1)+band(i+2))*0.25,f);
}
void main() {
    if(u.flags.w<0.0) { fragColor=vertexColor; return; }
    float pixelY=flameUv.y*u.metrics.z;
    float baseline=u.geometry.y,area=u.geometry.x;
    bool reflection=pixelY>baseline;
    if(reflection && baseline>=u.metrics.z-0.5) discard;
    float y=reflection?(pixelY-baseline)/max(area*0.5,1.0):(baseline-pixelY)/max(area,1.0);
    if(y<0.0 || y>1.0) discard;
    float time=u.flameInfo.x;
    float aspect=clamp(u.metrics.y/max(area,1.0),1.0,8.0);
    vec2 p=vec2(flameUv.x*aspect*4.5,y*2.3-time*1.4);
    // Advected multi-scale noise bends rising tongues and opens rolling gaps.
    float flow=turbulence(p*0.65+vec2(0,-time*0.23));
    float warp=(flow-0.5)*0.055*y;
    float fuel=fuelAt(flameUv.x+warp);
    if(fuel<0.002) discard;
    p.x+=(flow-0.5)*1.8*y;
    float billow=turbulence(p);
    float height=fuel*1.25;
    float envelope=height-y;
    float holes=turbulence(p*1.6+vec2(3.4,-time*0.5));
    float density=envelope-(1.0-billow)*(fuel*0.9+y*0.65);
    density-=smoothstep(0.48,0.75,holes)*smoothstep(0.06,0.25,y)*fuel*0.4;
    float aa=max(fwidth(density),0.006);
    float alpha=smoothstep(-aa,0.018+aa,density)*smoothstep(0.0,0.045,fuel);
    alpha*=1.0-smoothstep(0.82,1.0,y);
    float heat=clamp(density/max(fuel*0.65,0.02),0.0,1.0);
    vec3 warm=mix(u.bottomColor.rgb,u.middleColor.rgb,smoothstep(0.0,0.45,heat));
    vec3 color=mix(warm,u.topColor.rgb,smoothstep(0.32,0.90,heat));
    color=mix(color,vec3(1.0,0.96,0.76),smoothstep(0.72,1.0,heat)*0.50);
    if(u.flameInfo.z>0.5) color=u.flameInfo.w>0.5?vec3(0):vec3(1);
    if(reflection) alpha*=0.18*(1.0-y);
    alpha*=u.metrics.x;
    fragColor=vec4(color*alpha,alpha);
}
