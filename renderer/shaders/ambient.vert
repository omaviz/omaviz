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
    vec4 history[160]; // spectral drive, waveform, emission clock, emission energy
} u;
const float PI=3.141592653589793;
float band(int i) { vec4 v=u.levels[i/4];return v[i%4]; }
vec4 palette(float t) {
    if(u.flags.z>0.5) {
        if(u.scene.w<0.5) return primitive.x<0.5?vec4(1.0,0.65,0.36,1.0):vec4(0.78,0.79,0.84,1.0);
        if(u.scene.w<1.5) return mix(vec4(0.51,0.54,0.62,1),vec4(0.83,0.84,0.88,1),t);
        if(u.scene.w>2.5) return t<0.5?mix(vec4(0.12,0.75,0.94,1),vec4(0.48,0.24,0.92,1),t*2.0):mix(vec4(0.48,0.24,0.92,1),vec4(1.0,0.64,0.40,1),t*2.0-1.0);
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
    float presence=smoothstep(0.0,u.scene.w>4.5?0.0005:0.025,energy);
    if(u.scene.w>4.5) {
        if(id<0.5) {
            p=position;local=corner;shape=vec4(5,0,0,0);
        } else {
            // A world-space star volume expands past the camera. More distant
            // sky stars have slower parallax, retaining the sense of scale.
            vec2 field=vec2(fract(seed.x*17.7+id*0.37),fract(seed.y*13.1+id*0.61))*2.0-1.0;
            vec2 heading=vec2(0.03*sin(time*0.07),0.02*cos(time*0.05));
            bool distant=mod(id,3.0)<1.0;
            float depth=fract(fract(id*0.618034)-time*(distant?0.025:0.14));
            float z=distant?8.0+depth*26.0:0.35+depth*22.0;
            vec2 offset=field*u.surface.yz*(distant?16.0:12.0)/z;
            p=center+offset-heading*size*(distant?1.0:1.0+2.0/z);
            float starScale=max(u.surface.w,size/540.0);
            float radius=distant?starScale*(0.65+0.55*(1.0-depth)):max(starScale*0.90,min(size*0.009,3.4*size*0.004/z));
            float luminosity=pow(fract(id*0.56984),12.0);
            radius*=1.0+luminosity*1.7;
            local=corner*2.0;shape=vec4(6,0,0,0);
            p+=corner*radius*2.0;
            float temperature=fract(id*0.754878);
            tint=mix(vec4(0.68,0.80,1,1),vec4(1,0.89,0.72,1),temperature);
            if(u.flags.x>0.5) tint=vec4(vec3(1.0-u.flags.w),1.0);
            // Music changes the integrated travel clock, never star population
            // or brightness. Approaching stars gain light continuously with depth.
            float approach=pow(1.0-depth,1.15);
            float light=distant?mix(0.20,0.65,approach):mix(0.12,1.0,approach);
            tint.a*=presence*light*(0.7+luminosity*2.0)
                      *smoothstep(0.0,distant?0.04:0.018,depth)*(1.0-smoothstep(0.94,1.0,depth));
        }
    } else if(u.scene.w>3.5) {
        // A full viewport surface: the fragment shader shades the tunnel interior.
        p=position;local=corner;shape=vec4(4,0,0,0);
    } else if(u.scene.w<0.5) {
        float radius=size*0.43*(0.19+0.81*(id+1.0)/count);
        // Outer rings form a fan that changes direction and opens with music;
        // inner rings respond independently. Avoid a perpetually spinning wheel.
        float bass=(band(0)+band(1)+band(2)+band(3))*0.25;
        float sweep=0.25+1.55*(0.30*energy+0.70*level);
        float fan=0.55+0.70*sin(time*2.1)+0.80*(bass-0.4)-0.50*pulse;
        float start=id<3.0
            ? 2.1+id*1.4+sin(time*(1.9+id*0.4)+id)*1.8+level*0.8
            : fan-sweep*0.5+(id-6.0)*0.075+0.25*sin(time*1.9+id*0.3)+0.60*(level-0.5);
        float articulation=0.65+0.35*level;
        float stroke=max(u.surface.w*0.8,size*(compact>0.5?0.032:0.013));
        float extent=stroke*0.5+u.surface.w;
        float t=(corner.x+1.0)*0.5;
        float angle=start+sweep*(primitive.z>0.5?(primitive.z<1.5?0.0:1.0):t);
        vec2 normal=vec2(cos(angle),sin(angle)),tangent=vec2(-normal.y,normal.x);
        p=center+normal*radius;
        if(primitive.z<0.5) p+=normal*corner.y*extent;
        else p+=(tangent*corner.x+normal*corner.y)*extent;
        shape.y=stroke*0.5/extent;
        tint.a*=u.flags.z>0.5&&id<0.5?presence*(0.70+0.30*energy):presence*(0.08+0.92*level*level)*(0.35+0.65*articulation);
    } else if(u.scene.w<1.5) {
        float x=id/max(1.0,count-1.0),row=primitive.y;
        // History rows travel continuously away from the bright leading edge.
        // A new row enters as the oldest fades out at the vanishing side.
        float depth=(row+u.layoutInfo.w)/u.layoutInfo.y;
        float column=x*19.0;
        int lo=int(column),hi=min(lo+1,19),r=int(row)*20;
        vec4 snapshot=mix(u.history[r+lo],u.history[r+hi],fract(column));
        vec2 drive=snapshot.xy;
        drive.y=drive.y*0.5+(u.history[r+max(0,lo-1)].y+u.history[r+min(19,hi+1)].y)*0.25;
        float field=min(u.surface.z,u.surface.y*0.95);
        float rowEnergy=snapshot.w;
        // The emitted contour comes entirely from music, never a timed carrier.
        float spectrum=max(0.0,(drive.x-rowEnergy*0.60)*2.5);
        float contour=clamp(drive.y*0.36+(spectrum-rowEnergy*0.25)*0.62,-0.4,0.4);
        float amplitude=0.30+0.65*rowEnergy;
        float y=u.surface.z*0.5+field*(0.14-depth*0.30
                      -contour*amplitude);
        float drift=drive.y*u.surface.y*0.012*rowEnergy;
        float side=min(u.surface.y/count*0.88,field*(compact>0.5?0.14:0.095))*(1.0-depth*0.38);
        p=vec2(u.surface.y*0.5+(x-0.5)*u.surface.y*0.92*(1.0-depth*0.27)+drift,y)+corner*side*0.5;
        shape.y=2.0*u.surface.w/max(side,1.0);
        tint=palette(x);tint.a*=presence*(0.68+0.32*drive.x)*pow(1.0-depth,1.3);
    } else if(u.scene.w>2.5) {
        float rings=compact>0.5?12.0:22.0;
        float pearls=compact>0.5?4.0:8.0;
        bool pearl=primitive.z>2.5;
        // Depth moves toward the viewer; wrap happens beyond the viewport.
        float travel=time*0.16;
        float depth=fract((pearl?(id-rings+0.37)/pearls:id/rings)-travel);
        float z=0.20*pow(400.0,depth);
        float projection=1.0/z;
        float bass=(band(0)+band(1)+band(2)+band(3))*0.25;
        float treble=(band(16)+band(20))*0.5;
        vec2 bend=vec2(sin(time*0.23+depth*2.8),cos(time*0.17+depth*2.1));
        vec2 axis=center+size*0.25*bend*depth+size*vec2(bass-treble,treble-bass*0.5)*0.045;
        float radius=size*0.78*projection*(1.0+0.12*bass*sin(depth*13.0-time*1.4)+0.06*pulse);
        float fade=smoothstep(0.0,0.035,depth);
        tint=palette(0.5+0.5*sin(depth*4.5-time*0.12));
        if(!pearl) {
            float angle=(corner.x+1.0)*PI+time*0.07;
            float ripple=1.0+0.009*level*sin(angle*6.0+depth*9.0-time);
            vec2 normal=vec2(cos(angle),sin(angle));
            float stroke=max(u.surface.w*0.65,size*0.003*projection*(0.85+0.5*energy+0.5*pulse));
            float extent=stroke+u.surface.w*1.3;
            p=axis+normal*(radius*ripple+corner.y*extent);
            local=vec2(0,corner.y);shape=vec4(0,stroke*0.35/extent,0,0);
            float density=0.34+0.66*smoothstep(0.06,0.78,energy);
            float visibility=1.0-smoothstep(density-0.055,density+0.055,fract(id*0.618034));
            tint.a*=presence*fade*visibility*(0.26+0.42*(1.0-depth)+0.30*bass+0.25*pulse);
        } else {
            float angle=id*2.39996+time*0.14+depth*0.9;
            vec2 orbit=vec2(cos(angle),sin(angle));
            float pearlRadius=max(u.surface.w,size*0.023*projection*(0.8+0.35*level));
            p=axis+orbit*radius*(0.30+0.24*sin(id*1.7))*vec2(1,1)+corner*pearlRadius*1.12;
            local=corner*1.12;shape=vec4(2,0.10,-0.6,-0.8);
            tint=palette(0.75+0.25*sin(id));
            tint.a*=presence*fade*(0.45+0.55*band(12+int(id)%12));
        }
    } else {
        float angle=time*0.70;
        vec3 q=vec3(seed.x*cos(angle)+seed.z*sin(angle),seed.y,-seed.x*sin(angle)+seed.z*cos(angle));
        float depth=clamp((q.z+1.0)*0.5+0.14*sin(time*0.55+id*1.73),0.0,1.0);
        float projection=1.0/(1.20+q.z*0.24);
        vec2 drift=vec2(sin(time*0.83+id*1.73),cos(time*0.71+id*2.31))*(0.045+0.09*level);
        vec2 offset=q.xy*projection+drift;
        offset*=min(1.0,0.84/max(length(offset),0.001));
        p=center+offset*size*(0.34+0.30*energy+0.07*pulse+0.035*level);
        float focus=abs(depth-(0.22+0.35*energy))*1.9;
        float radius=size*(compact>0.5?0.047:0.038)*(0.65+1.25*depth)*(0.75+0.45*energy+0.10*level+0.06*pulse);
        float blur=0.025+focus*0.90;
        float extent=radius*(1.0+blur);
        p=clamp(p,vec2(extent),u.surface.yz-vec2(extent));
        p+=corner*extent;
        local=corner*(1.0+blur);shape.y=blur;
        shape.zw=vec2(cos(id*2.39+time*0.3),sin(id*2.39+time*0.3));
        float glint=pow(clamp(1.0-focus,0.0,1.0),3.0);
        float excitation=0.55*energy+0.45*level;
        tint.a*=presence*(0.18+1.20*excitation)*(0.45+glint+0.85*pulse)*(0.72+0.28*(1.0-depth));
    }
    tint.a*=u.surface.x;
    gl_Position=u.matrix*vec4(p,0,1);
}
