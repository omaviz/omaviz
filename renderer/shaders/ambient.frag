#version 440
layout(location=0) in vec4 tint;
layout(location=1) in vec2 local;
layout(location=2) in vec4 shape;
layout(location=0) out vec4 fragColor;
void main() {
    float coverage=1.0;
    if(shape.x<0.5) {
        // End caps occupy only the half outside the strip: no bright overlap.
        if((shape.z>0.5&&shape.z<1.5&&local.x>0.0)||(shape.z>1.5&&local.x<0.0))discard;
        float distance=shape.z>0.5?length(local):abs(local.y);
        coverage=1.0-smoothstep(shape.y,1.0,distance);
    } else if(shape.x<1.5) {
        float edge=max(abs(local.x),abs(local.y));
        coverage=1.0-smoothstep(1.0-max(shape.y,0.005),1.0,edge);
    } else {
        float radius=length(local),blur=max(shape.y,fwidth(radius));
        float edge=1.0-smoothstep(1.0-blur,1.0+blur,radius);
        float rim=exp(-pow((radius-0.83)/(0.055+blur*0.60),2.0));
        float illumination=pow(clamp(0.5+0.5*dot(local,shape.zw),0.0,1.0),2.0);
        float focused=0.24+0.76*illumination+0.12*rim;
        float defocused=exp(-1.4*radius*radius);
        float lens=mix(focused,defocused,smoothstep(0.08,0.45,blur));
        coverage=edge*lens;
    }
    float alpha=clamp(tint.a*coverage,0.0,1.0);
    fragColor=vec4(tint.rgb*alpha,alpha);
}
