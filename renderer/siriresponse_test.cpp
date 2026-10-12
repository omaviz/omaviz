#include "siriresponse.h"
#include <cstdio>
#include <cstdlib>
#include <limits>
void check(bool ok,const char *what) { if(!ok) {fprintf(stderr,"%s\n",what);std::exit(1);} }
int main() {
    SiriResponse response;
    const float dt=1.f/60, target=SiriResponse::target(.1f,1);
    response.step(.1f,1,dt);
    check(response.energy>target*.4f,"first audio frame must respond immediately");
    check(response.layers.front()>response.layers.back(),"sheets need slightly staggered attacks");
    for(int i=1;i<6;++i)response.step(.1f,1,dt);
    check(response.energy>target*.95f,"attack must reach 95 percent within 100ms");
    for(int i=0;i<15;++i)response.step(0,1,dt);
    check(response.energy<target*.13f,"pause must shed at least 87 percent within 250ms");
    for(int i=0;i<120;++i)response.step(0,1,dt);
    check(response.energy==0,"silence must settle completely");
    const float stopped=response.motion;
    for(int i=0;i<60;++i)response.step(0,1,dt);
    check(response.motion==stopped,"silence must not keep travelling");
    float previous=0;
    for(float rms:{.003f,.01f,.03f,.07f,.15f,.3f,.6f,1.f}) {
        float current=SiriResponse::target(rms,1);
        check(current>previous+.01f && current<1,"loudness levels must stay distinct without clipping");
        check(SiriResponse::visible(current,32)<1,"mini must retain headroom too");
        previous=current;
    }
    SiriResponse soft,loud,burst;
    for(int i=0;i<90;++i){soft.step(.015f,1,dt);loud.step(.15f,1,dt);}
    check(loud.motion>soft.motion*1.5f,"travel should follow loudness, not just time");
    for(int i=0;i<6;++i)burst.step(.15f,1,dt);
    for(int i=0;i<12;++i)burst.step(0,1,dt);
    const float trough=burst.energy;
    burst.step(.15f,1,dt);
    check(burst.energy>trough*2 && burst.pulse>.5f,"next syllable must give a distinct new attack");
    SiriResponse regular,batched;
    for(int i=0;i<60;++i)regular.step(.1f,1,dt);
    for(int i=0;i<30;++i)batched.step(.1f,1,dt*2);
    check(std::abs(regular.motion-batched.motion)<.00001f,"frame batching must not change ribbon travel");
    check(std::abs(regular.energy-batched.energy)<.00001f,"frame batching must not change amplitude");
    // A centered lobe stays anchored throughout a birth; travel goes right.
    regular.motion=.20f;
    const auto centered=regular.lobe(0,250,false), travelling=regular.lobe(0,250,true);
    regular.motion=.30f;
    check(regular.lobe(0,250,false).center==centered.center,"centered lobes must not scroll");
    check(regular.lobe(0,250,true).center>travelling.center,"travel must advance left to right");
    bool vanished=false,varied=false;
    for(int frame=0;frame<600;++frame) {
        regular.motion=frame/60.f;
        const auto a=regular.lobe(0,250,false),b=regular.lobe(1,250,false);
        vanished|=a.opacity==0;
        varied|=a.height>b.height*2 && b.height>0;
        for(int layer=0;layer<6;++layer)for(bool travel:{false,true}) {
            auto l=regular.lobe(layer,250,travel);
            check(std::isfinite(l.height)&&l.height>=0&&l.height<.5f,"lobes must fit vertically");
            check(l.center-l.radius>0 && l.center+l.radius<1,"lobes must fit horizontally");
        }
    }
    check(vanished && varied,"lobes need independent sizes and complete disappearance");
    SiriResponse bass,treble;
    std::array<float,6> lows{.1f,0,0,0,0,0}, highs{0,0,0,0,0,.1f};
    for(int i=0;i<90;++i) { bass.step(.1f,1,dt,&lows); treble.step(.1f,1,dt,&highs); }
    check(std::abs(bass.energy-treble.energy)<.00001f,"equal RMS must preserve overall loudness");
    check(bass.layers[0]>treble.layers[0]*4 && treble.layers[5]>bass.layers[5]*4,
          "equal RMS with different frequencies must excite different layers");
    for(int i=0;i<90;++i)bass.step(.1f,1,dt,&highs);
    check(bass.layers[5]>bass.layers[0]*3,"layers must follow a frequency change at constant RMS");
    lows.fill(0);
    for(int i=0;i<180;++i)bass.step(0,1,dt,&lows);
    for(int i=0;i<6;++i) {
        check(bass.layers[i]==0,"every layer must settle in silence");
        check(bass.lobe(i,250,false).opacity==0,"silent lobes must leave only the axis");
    }
    check(treble.layers[0]==0,"inactive frequency must have no shared amplitude floor");
    response.step(std::numeric_limits<float>::quiet_NaN(),1,dt);
    check(std::isfinite(response.energy),"invalid samples must not poison the response");
    puts("Siri response: attack, release, dynamic range, silence, articulation PASS");
}
