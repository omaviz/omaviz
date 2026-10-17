#include "ambientresponse.h"
#include <cstdio>
#include <cstdlib>
#include <limits>
static void check(bool ok,const char *message) { if(!ok){fprintf(stderr,"FAIL: %s\n",message);std::exit(1);} }
int main() {
    constexpr float dt=1.f/60;
    std::array<float,AmbientResponse::Bands> input{};
    std::array<float,AmbientResponse::Columns> wave{};
    input[3]=.2f;wave[4]=.7f;
    AmbientResponse regular,batched;
    for(int i=0;i<60;++i)regular.step(input,wave,1,dt);
    for(int i=0;i<30;++i)batched.step(input,wave,1,dt*2);
    check(std::abs(regular.energy-batched.energy)<.00001f,"batched frames preserve energy");
    check(std::abs(regular.motion-batched.motion)<.00001,"batched frames preserve travel");
    check(regular.energy>.3f && regular.energy<.9f,"narrow-band music excites the whole scene without clipping");
    check(regular.levels[3]>.4f && regular.levels[2]==0,"individual spectral excitation remains distinct");
    check(regular.history[0][0]>0 && regular.history[7][19]>0,"pixel field remains coherent across frequencies");
    float previous=0;
    for(float gain:{.1f,.5f,1.f,2.f,4.f}) {
        float v=AmbientResponse::target(.1f,gain);
        check(v>previous && v<1,"sensitivity retains headroom and ordered loudness");previous=v;
    }
    // Equal normalized spectra must still distinguish quiet/loud PCM.
    AmbientResponse quiet,loud;
    for(int i=0;i<60;++i) {
        quiet.step(input,wave,1,dt,.03f);
        loud.step(input,wave,1,dt,.18f);
    }
    check(loud.energy>quiet.energy*2,"PCM loudness retains musical dynamic range");
    AmbientResponse faint;
    for(int i=0;i<60;++i) faint.step(input,wave,1,dt,.002f);
    check(faint.energy>.05f && faint.energy<quiet.energy*.5f,"quiet audible PCM stays visible and distinct from normal audio");
    check(std::abs(quiet.motion-loud.motion)<.00001,"drift does not become a shared audio-speed motor");
    AmbientResponse quietTravel,loudTravel;
    for(int i=0;i<60;++i) {
        quietTravel.step(input,wave,1,dt,.03f,false,1.f/30,true);
        loudTravel.step(input,wave,1,dt,.18f,false,1.f/30,true);
    }
    check(loudTravel.motion>quietTravel.motion*1.3,
          "tunnel travel follows PCM loudness even when normalized spectra match");
    AmbientResponse compatibility;
    compatibility.step(input,wave,1,dt,-1,true);
    check(compatibility.energy>0,"Pixel Wave retains its spectral response");
    AmbientResponse trail;
    for(int i=0;i<7;++i)trail.step(input,wave,1,dt,-1,true,.105f);
    const double emitted=trail.motionHistory[0];
    const float emittedEnergy=trail.energyHistory[0];
    for(int i=0;i<3;++i)trail.step(input,wave,1,dt,-1,true,.105f);
    check(trail.motionHistory[0]==emitted && trail.energyHistory[0]==emittedEnergy,
          "emitted Pixel Wave rows retain their captured shape between emissions");
    for(int i=0;i<3;++i)trail.step(input,wave,1,dt,-1,true,.105f);
    check(trail.motionHistory[1]==emitted && trail.motionHistory[0]>emitted,
          "Pixel Wave moves the previous snapshot into its fading tail");
    input.fill(0);wave.fill(0);
    for(int i=0;i<96;++i)regular.step(input,wave,1,dt);
    check(regular.energy==0,"energy settles inside the animation tail");
    for(float v:regular.levels)check(v==0,"all frequency envelopes settle");
    for(auto row:regular.history)for(float v:row)check(v==0,"delayed rows clear after release");
    const double stopped=regular.motion;regular.step(input,wave,1,dt);
    check(regular.motion==stopped,"silent response does not keep advancing");
    input[0]=std::numeric_limits<float>::infinity();wave[0]=std::numeric_limits<float>::quiet_NaN();
    regular.step(input,wave,std::numeric_limits<float>::quiet_NaN(),dt);
    regular.step(input,wave,1,std::numeric_limits<float>::infinity());
    check(std::isfinite(regular.energy) && std::isfinite(regular.motion),"nonfinite values cannot poison the response");
    for(float v:regular.wave)check(std::isfinite(v),"wave history sanitizes invalid samples");
    puts("Ambient response: dynamic range, frame batching, narrow bands, history, silence, invalid input PASS");
}
