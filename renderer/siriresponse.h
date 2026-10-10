#pragma once
#include <algorithm>
#include <array>
#include <cmath>

// Shared by the retained renderer and its CPU comparison path. The audio
// controls both the envelope and travel; absolute wall-clock time never does.
struct SiriResponse {
    std::array<float,6> layers{};
    float energy=0, pulse=0, motion=0, previousTarget=0;
    static float target(float rms,float gain) {
        if(!std::isfinite(rms)) rms=0;
        if(!std::isfinite(gain)) gain=1;
        const float level=std::max(0.f,rms-.001f)*std::clamp(gain,.1f,4.f);
        // A soft knee retains loudness differences instead of pinning all
        // ordinary/loud input at the old hard ceiling.
        return std::pow(level/(.055f+level),.45f);
    }
    void step(float rms,float gain,float dt,const std::array<float,6> *spectrum=nullptr,bool ribbons=false) {
        dt=std::isfinite(dt)?std::clamp(dt,0.f,.1f):0;
        if(dt==0)return;
        const float drive=target(rms,gain);
        const float pulseStart=std::max(pulse,std::min(1.f,std::max(0.f,drive-previousTarget)*3.f));
        pulse=pulseStart*std::exp(-dt/.070f);
        previousTarget=drive;
        const bool active=energy>0 || drive>0;
        const float globalTau=drive>energy?.024f:.110f;
        const float globalDecay=std::exp(-dt/globalTau);
        const float energyIntegral=drive*dt+(energy-drive)*globalTau*(1-globalDecay);
        energy=drive+(energy-drive)*globalDecay;
        if(energy<.0001f)energy=0;
        constexpr float weight[]={1.f,.76f,.92f,.68f,.84f,.60f};
        for(int i=0;i<6;++i) {
            // 18–38 ms attack and 95–135 ms release: immediate articulation
            // with a small stagger between lobes, rather than a uniform swell.
            // No global amplitude floor: an unexcited lobe must disappear.
            const float spectral=spectrum?target((*spectrum)[i],gain):drive;
            const float local=ribbons && spectrum?.15f*drive+.85f*spectral:spectral;
            const float layerDrive=local*weight[i];
            const float tau=layerDrive>layers[i]?.018f+i*.004f:.095f+i*.008f;
            const float decay=std::exp(-dt/tau);
            layers[i]=layerDrive+(layers[i]-layerDrive)*decay;
            if(layers[i]<.0001f)layers[i]=0;
        }
        // Integrate exponential envelopes analytically: dropped/combined
        // render frames must not change the speed or response trajectory.
        if(active)motion+=.30f*dt+2.2f*energyIntegral+4.f*(pulseStart-pulse)*.070f;
    }
    float phase(int layer,float amplitude,bool travel) const {
        return layer*.83f+(travel?motion*(1.8f+.27f*layer):.8f*amplitude+.35f*pulse);
    }
    struct Lobe { float center, radius, height, opacity; };
    static float smooth(float x) { x=std::clamp(x,0.f,1.f); return x*x*(3-2*x); }
    static float hash(int cycle,int layer,int salt) {
        // Stable per-birth variation, independent of render rate and surface.
        unsigned n=unsigned(cycle)*747796405u+unsigned(layer+salt)*2891336453u;
        n=(n^(n>>16))*2246822519u; n=(n^(n>>13))*3266489917u;
        return float((n^(n>>16))&65535u)/65535.f;
    }
    Lobe lobe(int i,float surfaceHeight,bool travel) const {
        constexpr float offsets[]={.18f,.43f,.67f,.05f,.81f,.32f};
        constexpr float centers[]={.43f,.51f,.57f,.30f,.70f,.49f};
        const float clock=motion*(.34f+.037f*i)+offsets[i];
        const int birth=int(std::floor(clock));
        const float life=clock-birth;
        // Smooth birth and disappearance, with a quiet gap between lobes.
        const float envelope=smooth(life/.22f)*(1-smooth((life-.58f)/.32f));
        const float amplitude=visible(layers[i],surfaceHeight);
        const float extent=.080f+.075f*hash(birth,i,7)+.030f*amplitude;
        const float center=travel?.17f+.66f*life:
            centers[i]+.10f*(hash(birth,i,3)-.5f);
        const float height=.26f*std::pow(amplitude,1.5f)*envelope
            *(.55f+.70f*hash(birth,i,11));
        return {center,extent*(.80f+.20f*envelope),height,
                envelope*smooth(amplitude/.12f)};
    }
    static float visible(float energy,float height) {
        const float boost=height<48?.5f:.1f;
        return energy*(1+boost)/(1+boost*energy);
    }
};
