#pragma once
#include <algorithm>
#include <array>
#include <cmath>

// Audio envelopes and a small 30 Hz history stay on the CPU. No geometry or
// particle positions live here; those are evaluated by the retained shaders.
struct AmbientResponse {
    static constexpr int Bands=24, Columns=20, Rows=8;
    std::array<float,Bands> levels{};
    std::array<float,Columns> wave{};
    std::array<std::array<float,Columns>,Rows> history{}, waveHistory{};
    std::array<double,Rows> motionHistory{};
    std::array<float,Rows> energyHistory{};
    float energy=0, pulse=0, previous=0, historyTime=0;
    double motion=0;
    static float unit(float x) { return std::isfinite(x)?std::clamp(x,0.f,1.f):0; }
    static float target(float x,float gain) {
        gain=std::isfinite(gain)?std::clamp(gain,.1f,4.f):1;
        return 1-std::exp(-3.0f*unit(x)*gain);
    }
    static float follow(float value,float goal,float dt,float attack=.045f,float release=.14f) {
        const float result=goal+(value-goal)*std::exp(-dt/(goal>value?attack:release));
        return std::abs(result)<.0001f?0:result;
    }
    void step(const std::array<float,Bands> &input,const std::array<float,Columns> &trace,float gain,float dt,float rms=-1,bool legacy=false,float historyPeriod=1.f/30,bool travelClock=false) {
        dt=std::isfinite(dt)?std::clamp(dt,0.f,.1f):0;
        if(dt==0) return;
        gain=std::isfinite(gain)?std::clamp(gain,.1f,4.f):1;
        const auto response=[&](float v) {
            return legacy?1-std::exp(-2.2f*std::sqrt(unit(v))*gain):target(v,gain);
        };
        float maximum=0,power=0;
        for(int i=0;i<Bands;++i) {
            float v=unit(input[i]);maximum=std::max(maximum,v);power+=v*v/Bands;
            levels[i]=follow(levels[i],response(v),dt);
        }
        // Real PCM loudness preserves musical dynamics that peak-normalized bands
        // cannot. The gentle power curve keeps quiet audible input visible without
        // normalizing every passage to the same maximum. Old producers and synthetic scenes retain a spectral fallback.
        const float drive=!legacy && std::isfinite(rms) && rms>=0
            ? 1-std::exp(-5.5f*std::pow(unit(rms),.7f)*gain)
            : response(.65f*maximum+.35f*std::sqrt(power));
        const float decay=std::exp(-dt/(drive>energy?.045f:.14f));
        const float tau=drive>energy?.045f:.14f;
        const float integral=drive*dt+(energy-drive)*tau*(1-decay);
        const float pulseStart=std::max(pulse,std::min(1.f,std::max(0.f,drive-previous)*3));
        pulse=pulseStart*std::exp(-dt/.09f); previous=drive;
        // Travelling modes integrate loudness for continuous forward motion.
        // Other modes keep a steady drift clock and respond through geometry.
        if(energy>0 || drive>0) motion+=(legacy || travelClock)?.65*dt+2.1*integral:dt;
        energy=drive+(energy-drive)*decay;
        if(energy<.0001f) energy=0;
        for(int i=0;i<Columns;++i) {
            const float t=std::isfinite(trace[i])?std::clamp(trace[i],-1.f,1.f):0;
            wave[i]=follow(wave[i],t,dt,.07f,.07f);
        }
        historyTime+=dt;
        while(historyTime+1e-6f>=historyPeriod) {
            historyTime-=historyPeriod;
            for(int row=Rows-1;row>0;--row) {
                history[row]=history[row-1];waveHistory[row]=waveHistory[row-1];
                motionHistory[row]=motionHistory[row-1];energyHistory[row]=energyHistory[row-1];
            }
            motionHistory[0]=motion;energyHistory[0]=energy;
            for(int i=0;i<Columns;++i) {
                int band=i*(Bands-1)/(Columns-1);
                float local=0;
                for(int j=-2;j<=2;++j) local+=levels[std::clamp(band+j,0,Bands-1)]/5;
                history[0][i]=legacy?.6f*energy+.4f*local:.25f*energy+.75f*local;
                waveHistory[0][i]=wave[i];
            }
        }
    }
};
