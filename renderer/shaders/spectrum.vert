#version 440
layout(location=0) in vec2 position;
layout(location=1) in vec4 shape; // band, kind, bottom edge, palette section
layout(location=2) in float row;
layout(location=0) out vec4 vertexColor;
layout(std140,binding=0) uniform buf {
    mat4 matrix;
    vec4 metrics; // opacity, width, height, pixel
    vec4 geometry; // area, baseline, stack scale, palette stop
    vec4 flags; // horizontal, split palette, stacks, spike tip limit (-1 disabled)
    vec4 bottomColor;
    vec4 middleColor;
    vec4 topColor;
    vec4 capColor;
    vec4 reflectionColor;
    vec4 bands[512];
} u;
vec4 palette(float t,float opacity) {
    t=clamp(t,0.0,1.0);
    vec4 c=u.flags.y>0.5 ? (t<u.geometry.w?mix(u.bottomColor,u.middleColor,t/u.geometry.w)
                    :mix(u.middleColor,u.topColor,(t-u.geometry.w)/(1.0-u.geometry.w)))
                    :mix(u.bottomColor,u.topColor,t);
    // Match QColor's 16-bit channels, alpha scaling, and premultiplied 8-bit vertices.
    vec4 c16=floor(clamp(c,0.0,1.0)*65535.0+0.5);
    c16.a=floor(c16.a*opacity+0.5);
    vec4 c8=floor((c16+128.0)/257.0);
    return vec4(floor((c8.rgb*c8.a+127.0)/255.0),c8.a)/255.0;
}
void main() {
    int i=int(shape.x);vec4 pair=u.bands[i/2];
    vec2 values=(i%2==0)?pair.xy:pair.zw;
    float area=u.geometry.x,base=u.geometry.y,pixel=u.metrics.w;
    float bh=max(pixel,values.x*area),top=base-bh,bottom=base;
    float tip=min(bh,u.flags.w),kind=shape.y;
    if(kind<1.5) {
        if(kind>0.5)top=base-values.x*area;
        else if(u.flags.z>0.5) {bottom=row;top=min(row,max(top,row-3.0*u.geometry.z));}
        else if(u.flags.w>=0.0)top+=tip;
        top=clamp(top,0.0,u.metrics.z);bottom=clamp(bottom,0.0,u.metrics.z);
        if(u.flags.x<0.5&&u.flags.y>0.5) {
            float stop=clamp(base-area*u.geometry.w,top,bottom);
            if(shape.w<0.5)bottom=stop;else top=stop;
        }
    } else if(kind<2.5) {
        top=max(0.0,base-values.y*area-pixel);
        bottom=top+(values.y>=0.02?(u.flags.w>=0.0?pixel:2.0*pixel):0.0);
    } else if(kind<3.5) {
        top=base+2.0;bottom=top+min(values.x*area*0.5,max(0.0,u.metrics.z-base-2.0));
    } else bottom=top+tip;
    float y=mix(top,bottom,shape.z);
    gl_Position=u.matrix*vec4(position.x,y,0.0,1.0);
    if(kind>1.5&&kind<2.5)vertexColor=u.capColor;
    else if(kind>2.5&&kind<3.5)vertexColor=u.reflectionColor;
    else vertexColor=palette(u.flags.x>0.5&&kind<3.5?position.x/u.metrics.y:(base-y)/area,kind>0.5&&kind<1.5?0.1:1.0);
    vertexColor*=u.metrics.x;
}
