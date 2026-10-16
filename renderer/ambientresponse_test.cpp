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
    check(regular.energy>.4f && regular.energy<.9f,"narrow-band music excites the whole scene without clipping");
    check(regular.levels[3]>.5f && regular.levels[2]==0,"individual spectral excitation remains distinct");
    check(regular.history[0][0]>0 && regular.history[7][19]>0,"pixel field remains coherent across frequencies");
    float previous=0;
    for(float gain:{.1f,.5f,1.f,2.f,4.f}) {
        float v=AmbientResponse::target(.1f,gain);
        check(v>previous && v<1,"sensitivity retains headroom and ordered loudness");previous=v;
    }
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
