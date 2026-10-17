#version 440
layout(location=0) in vec4 tint;
layout(location=1) in vec2 local;
layout(location=2) in vec4 shape;
layout(location=0) out vec4 fragColor;
layout(std140,binding=0) uniform buf {
    mat4 matrix;
    vec4 surface;
    vec4 scene;
    vec4 layoutInfo;
    vec4 flags;
    vec4 bottomColor;
    vec4 middleColor;
    vec4 topColor;
    vec4 levels[6];
    vec4 history[160];
} u;
layout(binding=1) uniform sampler2D milkyWay;
vec3 wallColor(float t) {
    if(u.flags.x>0.5) return mix(vec3(1),vec3(0.12),u.flags.w);
    if(u.flags.z>0.5) return mix(vec3(0.08,0.50,0.75),vec3(0.75,0.16,0.55),t);
    return u.flags.y>0.5?(t<0.5?mix(u.bottomColor.rgb,u.middleColor.rgb,t*2.0):mix(u.middleColor.rgb,u.topColor.rgb,t*2.0-1.0))
                         :mix(u.bottomColor.rgb,u.topColor.rgb,t);
}
float band(int i) { vec4 v=u.levels[i/4];return v[i%4]; }
vec2 tunnelAxis(float z) {
    float bend=0.48+0.95*smoothstep(0.04,0.75,u.layoutInfo.w);
    return bend*vec2(0.64*sin(z*0.28),0.30*cos(z*0.20));
}
vec2 tunnelTangent(float z) {
    float bend=0.48+0.95*smoothstep(0.04,0.75,u.layoutInfo.w);
    return bend*vec2(0.1792*cos(z*0.28),-0.06*sin(z*0.20));
}
float hash31(vec3 p) {
    p=fract(p*0.1031);p+=dot(p,p.yzx+33.33);
    return fract((p.x+p.y)*p.z);
}
float noise3(vec3 p) {
    vec3 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);
    return mix(mix(mix(hash31(i),hash31(i+vec3(1,0,0)),f.x),
                   mix(hash31(i+vec3(0,1,0)),hash31(i+vec3(1,1,0)),f.x),f.y),
               mix(mix(hash31(i+vec3(0,0,1)),hash31(i+vec3(1,0,1)),f.x),
                   mix(hash31(i+vec3(0,1,1)),hash31(i+vec3(1,1,1)),f.x),f.y),f.z);
}
vec3 galaxy(vec2 sky,vec2 center,float scale,float angle,float time) {
    vec2 p=(sky-center)/scale;
    p=mat2(cos(angle),-sin(angle),sin(angle),cos(angle))*p;
    p.y*=2.5;
    float radius=length(p);
    float phi=atan(p.y,p.x)+log(max(radius,0.05))*2.5-time*0.002;
    float arms=pow(0.5+0.5*cos(phi*2.0),3.0);
    float disk=exp(-radius*2.4)*(0.35+0.65*arms);
    float core=exp(-radius*12.0);
    vec3 coreColor=u.flags.z>0.5?vec3(0.9,0.83,0.72):wallColor(0.5);
    return vec3(0.72,0.66,0.57)*disk*0.20+coreColor*core*0.40;
}
vec3 travellingGalaxy(vec2 sky,vec2 world,float seed,float extent,float angle,float time) {
    // Far bodies approach much more slowly than the foreground star volume.
    // Both angular size and position use the same depth, giving true parallax.
    float depth=fract(seed-time*0.003);
    float z=18.0+depth*12.0;
    vec2 drift=vec2(0.18*sin(time*0.07),0.12*cos(time*0.05));
    float fade=smoothstep(0.0,0.08,depth)*(1.0-smoothstep(0.90,1.0,depth));
    return galaxy(sky,(world-drift)/z,extent/z,angle,time)*fade;
}
vec3 cosmos(vec2 screen) {
    float time=u.scene.x,energy=u.scene.y;
    float aspect=u.surface.y/u.surface.z;
    vec2 sky=screen*vec2(aspect,1);
    vec2 heading=vec2(0.03*sin(time*0.07),0.02*cos(time*0.05));
    sky+=heading*2.0*min(u.surface.y,u.surface.z)/u.surface.z;
    // ESO/S. Brunier's real all-sky panorama, viewed toward the central bulge.
    // The oblique projection and very slow yaw preserve its astronomical detail.
    float angle=0.22;
    vec2 galactic=mat2(cos(angle),-sin(angle),sin(angle),cos(angle))*sky;
    galactic.x+=0.025*sin(time*0.015);
    vec2 uv=vec2(0.5+atan(galactic.x,1.25)/6.28318530718,
                 0.5+atan(galactic.y,length(vec2(galactic.x,1.25)))/3.14159265359);
    vec3 photograph=texture(milkyWay,uv).rgb;
    float bulge=exp(-galactic.x*galactic.x*1.8-galactic.y*galactic.y*12.0);
    if(u.flags.z<0.5) {
        // Tint the diffuse core while preserving resolved photographic stars.
        vec3 haze=min(photograph,textureLod(milkyWay,uv,3.0).rgb);
        vec3 starLight=photograph-haze;
        float light=dot(haze,vec3(0.299,0.587,0.114));
        vec3 tint=light*(vec3(0.20)+wallColor(0.5)*1.8);
        photograph=starLight+mix(haze,tint,bulge*0.95);
    }
    vec3 color=photograph*0.48;
    // Small galaxies enter in the outer field and drift outward with depth.
    // Their projected centres stay outside the central flight corridor.
    vec3 galaxies=travellingGalaxy(sky,vec2(19.5*aspect,-8.0),0.58,1.0,0.45,time);
    galaxies+=travellingGalaxy(sky,vec2(-19.5*aspect,-7.0),0.75,0.9,-0.6,time)*0.8;
    galaxies+=travellingGalaxy(sky,vec2(17.8*aspect,8.0),0.32,0.8,0.9,time)*0.6;
    color+=galaxies*0.65;
    if(u.flags.x>0.5) {
        float value=dot(color,vec3(0.299,0.587,0.114));
        color=u.flags.w>0.5?vec3(0.97-clamp(value,0.0,0.9)):vec3(value);
    }
    return color*smoothstep(0.0,0.0005,energy);
}
void main() {
    if(shape.x>5.5) {
        float radius=length(local);
        float glow=exp(-radius*radius*1.8)+0.10*exp(-radius*radius*0.32);
        // The Gaussian tail must reach zero before the quad boundary. A finite
        // circular support keeps close stars transparent outside their halo.
        float support=1.0-smoothstep(1.25,1.95,radius);
        float alpha=clamp(tint.a*glow*support,0.0,1.0);
        if(alpha<0.00025)discard;
        fragColor=vec4(tint.rgb*alpha,alpha);
        return;
    }
    if(shape.x>4.5) {
        fragColor=vec4(cosmos(local)*u.surface.x,u.surface.x);
        return;
    }
    if(shape.x>3.5) {
        float time=u.scene.x,energy=u.scene.y,pulse=u.scene.z;
        float bass=(band(0)+band(1)+band(2)+band(3))*0.25;
        float treble=(band(16)+band(18)+band(20)+band(23))*0.25;
        vec2 uv=local*vec2(u.surface.y/u.surface.z,1);
        float roll=0.035*sin(time*0.12)*(0.3+0.7*energy);
        uv=mat2(cos(roll),-sin(roll),sin(roll),cos(roll))*uv;
        vec3 camera=vec3(0,0,time*1.8);
        camera.xy+=tunnelAxis(camera.z);
        vec2 heading=(tunnelAxis(camera.z+3.0)-tunnelAxis(camera.z))*0.55;
        vec3 ray=normalize(vec3(uv*0.9+heading,1.35));
        float distance=0.0;
        float gap=1.0;
        // Conservative interior steps remain stable through the curved throat.
        for(int i=0;i<32;++i) {
            vec3 samplePoint=camera+ray*distance;
            float radius=1.0+0.012*bass*sin(samplePoint.z*0.7);
            gap=radius-length(samplePoint.xy-tunnelAxis(samplePoint.z));
            if(gap<0.004 || distance>60.0) break;
            distance+=max(0.003,gap*0.72);
        }
        vec3 point=camera+ray*distance;
        vec3 haze=wallColor(0.5+0.5*sin(time*0.23+treble))*0.25;
        vec3 color=haze;
        if(distance<59.0) {
            vec2 radial=point.xy-tunnelAxis(point.z);
            float angle=atan(radial.y,radial.x);
            vec2 bend=tunnelTangent(point.z);
            float breathing=0.0084*bass*cos(point.z*0.7);
            vec3 normal=normalize(vec3(-radial,dot(radial,bend)+breathing));
            vec3 light=normalize(camera+vec3(-0.35,-0.45,1.7)-point);
            float diffuse=max(0.0,dot(normal,light));
            // Precast lining rings, staggered into eight concrete segments.
            // Filter joints and bolt recesses as they recede into the throat.
            float ring=point.z/0.62;
            float sector=(angle/6.28318530718+0.5)*8.0+mod(floor(ring),2.0)*0.5;
            vec2 tile=fract(vec2(sector,ring));
            vec2 edge=min(tile,1.0-tile);
            vec2 aa=max(vec2(0.001),vec2((fwidth(sin(angle))+fwidth(cos(angle)))*1.28,fwidth(ring)));
            vec2 joint=smoothstep(vec2(0.009)-aa,vec2(0.009)+aa,edge);
            float grout=joint.x*joint.y;
            float bevel=smoothstep(0.012,0.06,min(edge.x,edge.y));
            float slab=hash31(vec3(floor(sector),floor(ring),1.0));
            float grain=noise3(point*18.0);
            vec3 concrete=vec3(0.48,0.49,0.47)*(0.86+0.16*slab+0.08*grain);
            float paletteT=0.5+0.5*sin(angle*0.5+point.z*0.12);
            vec3 pigment=u.flags.z>0.5?concrete:mix(concrete,wallColor(paletteT),0.70);
            vec3 illumination=u.flags.z>0.5?mix(vec3(0.75,0.84,1.0),vec3(1.0,0.85,0.68),0.5+0.5*sin(angle+time*0.12)):vec3(1.0);
            vec2 bolt=vec2(abs(tile.x-0.5)-0.31,tile.y-0.18);
            float boltDistance=length(bolt*vec2(1.0,0.65));
            float boltAA=max(aa.x,aa.y)*0.7;
            float recess=1.0-smoothstep(0.018-boltAA,0.018+boltAA,boltDistance);
            color=pigment*illumination*(0.25+0.80*diffuse)*(0.72+0.28*bevel);
            color*=mix(0.24,1.0,grout)*(1.0-0.60*recess);
            color+=wallColor(paletteT)*0.045*(0.5+bass+0.5*pulse);
            color=mix(color,haze,1.0-exp(-distance*0.045));
            color=mix(color,haze,smoothstep(0.004,0.08,gap));
            color*=0.7+0.3*energy+0.16*pulse;
        }
        // Restrained haze keeps distant joints legible without a polished sheen.
        float transmission=1.0;
        vec3 scatter=vec3(0);
        float fogStep=min(distance,12.0)/4.0;
        for(int i=0;i<4;++i) {
            vec3 p=camera+ray*(float(i)+0.5)*fogStep;
            float density=max(0.0,noise3(p*0.65)-0.35)*0.035;
            float alpha=1.0-exp(-density*fogStep);
            scatter+=transmission*wallColor(noise3(p*0.21))*alpha*0.45;
            transmission*=1.0-alpha;
        }
        color=color*transmission+scatter;
        // Opaque luminous depth has no hard black end cap or exterior leaks.
        color*=smoothstep(0.0,0.025,energy);
        if(u.flags.x>0.5) color=vec3(dot(color,vec3(0.299,0.587,0.114)));
        fragColor=vec4(color*u.surface.x,u.surface.x);
        return;
    }
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
