#include "geometry.h"
#include <QSGGeometryNode>
#include <QSGVertexColorMaterial>
#include <QQuickWindow>
#include <QColor>
#include <QElapsedTimer>
#include <cstdio>
#include <QVector2D>
#include <algorithm>
#include <cmath>
#include <vector>

namespace {
using Vertex = QSGGeometry::ColoredPoint2D;
float finite(float v, float fallback = 0) { return std::isfinite(v) ? v : fallback; }
float unit(float v) { return std::clamp(finite(v), 0.f, 1.f); }
QColor mix(const QColor &a, const QColor &b, float t) {
    t = unit(t);
    return QColor::fromRgbF(a.redF() + (b.redF()-a.redF())*t,
                           a.greenF() + (b.greenF()-a.greenF())*t,
                           a.blueF() + (b.blueF()-a.blueF())*t,
                           a.alphaF() + (b.alphaF()-a.alphaF())*t);
}
QColor alpha(QColor c, float a) { c.setAlphaF(unit(c.alphaF()*a)); return c; }
struct MeshNode : QSGGeometryNode {
    QSGGeometry mesh { QSGGeometry::defaultAttributes_ColoredPoint2D(), 0, 0, QSGGeometry::UnsignedIntType };
    QSGVertexColorMaterial material;
    std::vector<Vertex> vertices;
    std::vector<quint32> indices;
    QString mode;
    bool stripMode = false;
    int capacity = 0, indexCapacity = 0;
    std::vector<float> waveEnvelope;
    std::vector<float> stringEnvelope;
    int stringSamples = 0;
    std::vector<float> stringX, stringCarriers, stringModes;
    double lastPhase = 0;
    float siriEnergy = 0;
    qint64 buildNs = 0;
    int buildFrames = 0;
    ~MeshNode() override { if (qEnvironmentVariableIsSet("OMAVIZ_PROFILE")) fprintf(stderr,"geometry mean_cpu_ms %.4f frames %d\n",buildFrames?buildNs/1e6/buildFrames:0,buildFrames); }
    MeshNode() {
        mesh.setDrawingMode(QSGGeometry::DrawTriangles);
        mesh.setVertexDataPattern(QSGGeometry::DynamicPattern);
        material.setFlag(QSGMaterial::Blending);
        setGeometry(&mesh); setMaterial(&material);
        vertices.reserve(16384);
    }
    void vertex(float x, float y, QColor c) {
        Vertex v;
        // QSGVertexColorMaterial expects premultiplied vertex colors.
        const QRgb rgba = qPremultiply(c.rgba());
        v.set(x, y, qRed(rgba), qGreen(rgba), qBlue(rgba), qAlpha(rgba));
        indices.push_back(quint32(vertices.size())); vertices.push_back(v);
    }
    void packedVertex(QPointF p, QRgb c) {
        Vertex v; v.set(p.x(),p.y(),qRed(c),qGreen(c),qBlue(c),qAlpha(c)); vertices.push_back(v);
    }
    void packedQuad(QPointF a,QPointF b,QPointF c,QPointF d,QRgb ca,QRgb cb,QRgb cc,QRgb cd) {
        packedVertex(a,ca); packedVertex(b,cb); packedVertex(c,cc);
        packedVertex(a,ca); packedVertex(c,cc); packedVertex(d,cd);
    }
    void quad(QPointF a, QPointF b, QPointF c, QPointF d,
              QColor ca, QColor cb, QColor cc, QColor cd) {
        vertex(a.x(),a.y(),ca); vertex(b.x(),b.y(),cb); vertex(c.x(),c.y(),cc);
        vertex(a.x(),a.y(),ca); vertex(c.x(),c.y(),cc); vertex(d.x(),d.y(),cd);
    }
    void rect(float x,float y,float w,float h,QColor bottom,QColor top) {
        if (w <= 0 || h <= 0) return;
        quad({x,y},{x+w,y},{x+w,y+h},{x,y+h},top,top,bottom,bottom);
    }
    void upload() {
        const int count = int(vertices.size());
        const int indexCount=int(indices.size());
        if (count > capacity || indexCount > indexCapacity) {
            capacity=std::max(count,capacity*2); indexCapacity=std::max(indexCount,indexCapacity*2);
            mesh.allocate(capacity,indexCapacity);
        }
        mesh.setVertexCount(count); mesh.setIndexCount(indexCount);
        std::copy(indices.begin(),indices.end(),mesh.indexDataAsUInt());
        mesh.markIndexDataDirty();
        std::copy(vertices.begin(), vertices.end(), mesh.vertexDataAsColoredPoint2D());
        mesh.markVertexDataDirty(); markDirty(QSGNode::DirtyGeometry);
    }
};
// Continuous strips use shared miter joins, avoiding the bright overlapping
// segments and pinholes produced by drawing every line independently.
void ribbon(MeshNode &m, const std::vector<QPointF> &p, float halfWidth,
            QColor left, QColor right, float opacity, float feather,
            bool glow=false, float halo=18, float bloom=6, QColor middle=QColor()) {
    if(p.size()<2) return;
    // One continuous mesh represents the composed core/AA/bloom/halo profile.
    // It replaces three overlapping strokes without losing their glow shape.
    const int levels=glow?(m.stripMode?3:4):2, edges=levels*2;
    float distance[4]={0,feather,std::max(feather,bloom),std::max(feather,bloom)+.001f};
    if(glow && m.stripMode) distance[2]=std::max(feather+.001f,halo);
    else if(glow) distance[3]=std::max(distance[2]+.001f,halo);
    float coverage[4]{};
    for(int j=0;j<levels;++j) {
        const float d=distance[j];
        float core=opacity*std::max(0.f,1-d/feather);
        float inner=glow?.16f*std::max(0.f,1-d/std::max(.001f,bloom)):0;
        float outer=glow?.07f*std::max(0.f,1-d/std::max(.001f,halo)):0;
        coverage[j]=1-(1-core)*(1-inner)*(1-outer);
    }
    QRgb uniformColors[4];
    for(int j=0;j<levels;++j) uniformColors[j]=qPremultiply(alpha(left,coverage[j]).rgba());
    const bool uniform=left==right && !middle.isValid();
    quint32 previousStart=0;
    for(size_t i=0;i<p.size();++i) {
        QPointF normal;
        float radius=100000.f;
        if(m.stripMode) {
            // Smooth sampled strings share each cross-section. A central
            // tangent keeps width steady with one normalization per point.
            QPointF delta=p[std::min(i+1,p.size()-1)]-p[i?i-1:0];
            float length=std::sqrt(delta.x()*delta.x()+delta.y()*delta.y());
            if(length>.0001f) normal=QPointF(-delta.y()/length,delta.x()/length);
            else normal=QPointF(0,1);
        } else {
            QVector2D before(p[i]-p[i?i-1:i]);
            QVector2D after(p[i+1<p.size()?i+1:i]-p[i]);
            if(i==0) before=after;
            if(i+1==p.size()) after=before;
            float segmentLength=std::min(before.length(),after.length());
            before.normalize(); after.normalize();
            QVector2D n0(-before.y(),before.x()), n1(-after.y(),after.x());
            QVector2D n=(n0+n1).normalized();
            float scale=1.f/std::max(.5f,QVector2D::dotProduct(n,n1));
            normal=n.toPointF()*scale;
            float curvature=(n1-n0).length();
            radius=curvature>.001f?segmentLength/curvature:100000.f;
        }
        QPointF current[8]; QRgb colors[8];
        float t=float(i)/(p.size()-1);
        QColor base=uniform?left:middle.isValid()?(t<.5f?mix(left,middle,t*2):mix(middle,right,(t-.5f)*2)):mix(left,right,t);
        for(int j=0;j<levels;++j) {
            float offset=std::min(halfWidth+distance[j],std::max(halfWidth,radius*.7f));
            current[levels-1-j]=p[i]+normal*offset;
            current[levels+j]=p[i]-normal*offset;
            QRgb color=uniform?uniformColors[j]:qPremultiply(alpha(base,coverage[j]).rgba());
            colors[levels-1-j]=colors[levels+j]=color;
        }
        const quint32 start=quint32(m.vertices.size());
        for(int j=0;j<edges;++j) m.packedVertex(current[j],colors[j]);
        if(i && m.stripMode) {
            // One triangle strip per segment needs two indices per edge,
            // versus six per quad. Degenerate joins keep all strings batched.
            if(!m.indices.empty()) {
                m.indices.push_back(m.indices.back());
                m.indices.push_back(previousStart);
            }
            for(int j=0;j<edges;++j) {
                m.indices.push_back(previousStart+j);
                m.indices.push_back(start+j);
            }
        } else if(i) for(int j=0;j<edges-1;++j) {
            m.indices.insert(m.indices.end(),{previousStart+j,start+j,start+j+1,
                                             previousStart+j,start+j+1,previousStart+j+1});
        }
        previousStart=start;
    }
}
}

VisualGeometry::VisualGeometry(QQuickItem *parent):QQuickItem(parent) { setFlag(ItemHasContents); }
void VisualGeometry::setStyle(const QVariantMap &v) {
    if (m_style==v) return;
    m_style=v; emit styleChanged(); update();
}
void VisualGeometry::submit(const QVariantList &bars,const QVariantList &peaks,
                            const QVariantList &wave,double phase) {
    m_bars=bars; m_peaks=peaks; m_wave=wave; m_phase=phase; update();
}
void VisualGeometry::geometryChange(const QRectF &n,const QRectF &o) {
    QQuickItem::geometryChange(n,o); if(n.size()!=o.size()) update();
}
QSGNode *VisualGeometry::updatePaintNode(QSGNode *old,UpdatePaintNodeData *) {
    const QString mode=m_style.value("mode","Bars").toString();
    auto *node=static_cast<MeshNode *>(old);
    // A mode switch can change primitive topology and envelope state. Give
    // the scene graph a fresh node instead of reusing its cached pipeline.
    if(node && node->mode!=mode) { delete node; node=nullptr; }
    if(!node) { node=new MeshNode; node->mode=mode; }
    auto &m=*node; m.vertices.clear(); m.indices.clear();
    QElapsedTimer timer; timer.start();
    const float w=width(), h=height();
    if(w<=0 || h<=0) { m.upload(); return node; }
    auto number=[&](const char *k,float d){ return finite(m_style.value(k,d).toFloat(),d); };
    auto flag=[&](const char *k){ return m_style.value(k,false).toBool(); };
    auto color=[&](const char *k,const char *d){ auto c=m_style.value(k,QColor(d)).value<QColor>(); return c.isValid()?c:QColor(d); };
    const QColor bottom=color("bottom","#e68e0d"), top=color("top","#f59e0b");
    const bool mono=flag("mono"), fire=flag("fire"), horizontal=flag("horizontal");
    const QColor flat=flag("monoLight")?Qt::black:Qt::white;
    const QColor fireBottom=color("fireBottom","#be1400"), fireTop=color("fireTop","#fde047");
    const float dpr=window()?window()->effectiveDevicePixelRatio():1;
    const float pixel=1.f/std::max(1.f,dpr);
    auto palette=[&](float t) {
        if(mono) return flat;
        if(!fire && flag("middleEnabled")) {
            const QColor middle=color("middle","#a855f7");
            return t < .5f ? mix(bottom,middle,t*2) : mix(middle,top,(t-.5f)*2);
        }
        if(!fire) return mix(bottom,top,t);
        // Preserve the established three-stop flame palette.
        const QColor quarter=mix(fireBottom,QColor(255,130,10),0.25f/0.3f);
        return t<.25f?mix(fireBottom,quarter,t*4):mix(quarter,fireTop,(t-.25f)/.75f);
    };
    m.stripMode=mode=="Strings";
    m.mesh.setDrawingMode(m.stripMode?QSGGeometry::DrawTriangleStrip:QSGGeometry::DrawTriangles);
    if(mode=="Strings") {
        // The containing surface owns the backdrop; preserve alpha here.
        float energy=0;
        for(const auto &sample:m_wave) { float v=finite(sample.toFloat()); energy+=v*v; }
        energy=std::sqrt(energy/std::max(1,int(m_wave.size())));
        if(m.waveEnvelope.size()!=1) m.waveEnvelope.assign(1,0);
        float dt=std::clamp(m_phase-m.lastPhase,0.,.1);
        m.waveEnvelope[0]+=(energy-m.waveEnvelope[0])*(1-std::exp(-dt*5));
        m.lastPhase=m_phase;
        float amplitude=std::sqrt(unit((m.waveEnvelope[0]-.001f)*5.f));
        const float gain=std::clamp(number("gain",1),.1f,4.f);
        const QColor colors[]={QColor("#d8c889"),QColor("#bda76f"),QColor("#b78560"),
            QColor("#e6d7ad"),QColor("#c49a73"),QColor("#aebcbe")};
        // A narrow reference-sized surface still needs enough samples per
        // oscillation; pixel-width-only decimation made its arcs polygonal.
        const int count=std::clamp(int(w*dpr/4),48,224);
        if(m.stringSamples!=count) {
            m.stringSamples=count;
            m.stringX.resize(count);
            m.stringCarriers.resize(16*count);
            m.stringModes.resize(3*count);
            for(int i=0;i<count;++i) {
                const float x=float(i)/(count-1);
                m.stringX[i]=x;
                for(int mode=0;mode<3;++mode)
                    m.stringModes[mode*count+i]=std::sin(x*3.14159265f*(1+mode));
                for(int layer=0;layer<16;++layer) {
                    const bool foreground=layer>=13;
                    const float frequency=foreground?(.65f+(layer-13)*.38f):(2.1f+(layer%7)*.46f);
                    m.stringCarriers[layer*count+i]=std::sin(x*6.2831853f*frequency+layer*.83f);
                }
            }
        }
        std::vector<QPointF> points; points.reserve(count);
        std::vector<float> vibration(count,0);
        const int waveCount=int(m_wave.size());
        if(waveCount>4) {
            std::vector<float> filtered(waveCount,0);
            for(int i=0;i<waveCount;++i) {
                for(int tap=-4;tap<=4;++tap)
                    filtered[i]+=finite(m_wave[std::clamp(i+tap,0,waveCount-1)].toFloat());
                filtered[i]/=9.f;
            }
            for(int i=0;i<count;++i) {
                float position=float(i)/(count-1)*(waveCount-1);
                int lo=int(position), hi=std::min(lo+1,waveCount-1);
                vibration[i]=filtered[lo]+(filtered[hi]-filtered[lo])*(position-lo);
            }
        }
        if(m.stringEnvelope.size()!=16) m.stringEnvelope.assign(16,0);
        for(int layer=0;layer<16;++layer) {
            if(h<48 && layer%2) continue; // Preserve separation in the mini.
            const bool foreground=layer>=13;
            const bool distant=!foreground && layer%4==0;
            const float vibrationPhase=m_phase*(7.5f+layer*.68f)+layer*.47f;
            const float oscillation=std::sin(vibrationPhase);
            // Distinct FFT regions pluck distinct strings. Fast attack and a
            // slower release make each strand ring after the transient.
            float drive=0;
            if(!m_bars.isEmpty()) {
                int band=std::clamp(int((layer+.5f)/16*m_bars.size()),0,int(m_bars.size())-1);
                for(int tap=-2;tap<=2;++tap)
                    drive=std::max(drive,unit(m_bars[std::clamp(band+tap,0,int(m_bars.size())-1)].toFloat()));
            }
            // Perceptual compression lets ordinary playback visibly pluck
            // strings without requiring the user to raise global gain.
            drive=std::sqrt(drive);
            // The broad cool strands follow whole-signal motion. High-band
            // energy alone leaves them nearly flat on ordinary music.
            if(foreground) drive=std::max(drive,amplitude*.8f);
            float &ring=m.stringEnvelope[layer];
            ring+=(drive-ring)*(1-std::exp(-dt*(drive>ring?22.f:3.8f)));
            float extent=(.39f+.09f*std::sin(layer*2.1f))
                *std::clamp(amplitude*.35f+ring*.85f,0.f,1.f);
            points.clear();
            for(int i=0;i<count;++i) {
                float x=m.stringX[i];
                // The carrier shape stays fixed in x. Audio excites an
                // in-place standing mode whose nodes remain at the edges.
                const float stringMotion=extent*m.stringCarriers[layer*count+i]
                    *(.35f+.65f*oscillation);
                const float standingMotion=ring*.14f*std::sin(vibrationPhase*.71f+layer)
                    *m.stringModes[(layer%3)*count+i];
                const float audioMotion=vibration[i]*(amplitude*.3f+ring*.7f)*(foreground?.11f:.045f)
                    *std::sin(x*3.14159265f);
                float y=.5f+.46f*std::tanh(gain*(stringMotion+standingMotion+audioMotion)/.46f);
                points.emplace_back(x*w,y*h);
            }
            QColor tint=mono?flat:flag("custom")?palette(float(layer)/15):colors[foreground?5:layer%5];
            // Defocused blue foreground strings overlay finer warm strands.
            float size=std::clamp(h/360.f,.25f,1.5f);
            ribbon(m,points,(foreground?1.55f:.65f)*size*std::clamp(number("lineWidth",2)/2.f,.5f,2.5f),tint,tint,
                   foreground?.32f:(distant?.34f:.72f),
                   std::max(pixel,(foreground?3.3f:(distant?2.3f:1.1f))*size),h>=48,
                   (foreground?14.f:(distant?9.f:4.5f))*size,
                   (foreground?6.f:(distant?4.f:2.f))*size);
        }
    } else if(mode=="Siri") {
        // Translucent, intersecting sheets around a luminous central axis.
        // Geometry only: no per-frame textures or full-window blur passes.
        float rms=0;
        for(const auto &sample:m_wave) { float v=finite(sample.toFloat()); rms+=v*v; }
        rms=std::sqrt(rms/std::max(1, int(m_wave.size())));
        // Perceptual response: normal -26 dBFS playback must form visible
        // sheets, while silence and noise still settle to the axis.
        float target=std::pow(unit((rms-.001f)*8.f*std::clamp(number("gain",1),.1f,4.f)),.42f);
        float dt=std::clamp(float(m_phase-m.lastPhase),0.f,.1f);
        m.siriEnergy+=(target-m.siriEnergy)*(1-std::exp(-dt*(target>m.siriEnergy?14.f:5.f)));
        m.lastPhase=m_phase;
        const float visibleEnergy=unit(m.siriEnergy*(h<48?1.9f:1.2f));
        const int count=std::clamp(int(w*dpr/5),64,240);
        const QColor hues[]={QColor("#ba32dd"),QColor("#4936ca"),QColor("#087dda"),
            QColor("#00bde8"),QColor("#36ceef"),QColor("#acdfff")};
        for(int layer=0;layer<6;++layer) {
            const float center=.28f+.085f*layer+.055f*std::sin(float(m_phase)*.8f+layer), spread=.20f;
            const float speed=1.8f+.27f*layer, phase=float(m_phase)*speed+layer*.83f;
            std::vector<QPointF> upper, lower;
            upper.reserve(count); lower.reserve(count);
            auto shape=[&](float x) {
                float taper=std::sin(x*3.14159265f);
                float gaussian=std::exp(-std::pow((x-center)/spread,2.f)*.65f);
                float carrier=std::sin(x*(13.f+layer*1.3f)-phase);
                // Broad lobes keep their filled silhouette even at 24px.
                return taper*gaussian*(.24f+.76f*std::abs(carrier))*h*.47f*visibleEnergy*(1-.045f*layer);
            };
            QColor tint=mono?flat:flag("custom")?palette(float(layer)/5):hues[layer];
            for(int i=0;i<count;++i) {
                float x=float(i)/(count-1), y=shape(x);
                upper.emplace_back(x*w,h*.5f-y);
                lower.emplace_back(x*w,h*.5f+y*(.72f+.22f*std::sin(phase+x*8)));
            }
            for(int i=1;i<count;++i) {
                float x0=float(i-1)/(count-1), x1=float(i)/(count-1);
                float a0=std::pow(std::max(0.f,std::sin(x0*3.14159265f)),1.2f), a1=std::pow(std::max(0.f,std::sin(x1*3.14159265f)),1.2f);
                QColor rim0=alpha(tint,.48f*a0), rim1=alpha(tint,.48f*a1);
                QColor core0=alpha(tint,(layer==5?.22f:.46f)*a0), core1=alpha(tint,(layer==5?.22f:.46f)*a1);
                QPointF c0(x0*w,h*.5f), c1(x1*w,h*.5f);
                m.quad(upper[i-1],upper[i],c1,c0,rim0,rim1,core1,core0);
                m.quad(c0,c1,lower[i],lower[i-1],core0,core1,rim1,rim0);
            }
            ribbon(m,upper,.45f*pixel,tint,tint,.24f,pixel,true,std::min(h*.035f,5.f)*pixel,pixel);
            ribbon(m,lower,.4f*pixel,tint,tint,.18f,pixel,false);
        }
        std::vector<QPointF> axis={{0,h*.5f},{w*.5f,h*.5f},{w,h*.5f}};
        ribbon(m,axis,.22f*pixel,mono?flat:flag("custom")?palette(0):QColor("#a8e7ff"),mono?flat:flag("custom")?palette(1):QColor("#cdefff"),
               .10f+.12f*m.siriEnergy,pixel,false);
    } else if(mode=="Oscilloscope" || mode=="Wave" || mode=="Waves") {
        const int count=std::clamp(int(m_wave.size()),2,2048);
        const float gain=std::clamp(number("gain",1),.1f,4.f);
        float rms=0;
        for(const auto &sample:m_wave) { const float v=finite(sample.toFloat()); rms+=v*v; }
        rms=std::sqrt(rms/std::max(1,int(m_wave.size())));
        if(m.waveEnvelope.size()!=1) m.waveEnvelope.assign(1,0);
        const float dt=std::clamp(float(m_phase-m.lastPhase),0.f,.1f);
        m.waveEnvelope[0]+=(rms-m.waveEnvelope[0])*(1-std::exp(-dt*8));
        m.lastPhase=m_phase;
        const float displayGain=1/std::sqrt(std::clamp(m.waveEnvelope[0]*4,.05f,1.f));
        std::vector<QPointF> points; points.reserve(count);
        for(int i=0;i<count;++i) {
            float sample=i<m_wave.size()?finite(m_wave[i].toFloat()):0;
            points.emplace_back(float(i)*w/(count-1),h*.5f-std::clamp(sample*gain*displayGain,-1.f,1.f)*h*.43f);
        }
        ribbon(m,points,std::clamp(number("lineWidth",2),1.f,5.f)*.5f,
               palette(0),palette(1),1.f,pixel,false,18,6,
               !mono && !fire && flag("middleEnabled")?color("middle","#a855f7"):QColor());
    } else {
        const int n=m_bars.size();
        const bool reflect=flag("reflect"), spikes=flag("spikes"), stacks=flag("stacks");
        const float area=h*(reflect?.62f:1.f), base=h*(reflect?.68f:1.f);
        const float gap=spikes?0:std::max(0.f,number("gap",1));
        const float bw=spikes?w/std::max(n,1):std::max(pixel,(w-gap*std::max(n-1,0))/std::max(n,1))+number("extraWidth",0);
        auto rect=[&](float x,float y,float rw,float rh,float opacity=1.f) {
            float l=std::clamp(x,0.f,w), r=std::clamp(x+rw,0.f,w);
            float t=std::clamp(y,0.f,h), b=std::clamp(y+rh,0.f,h);
            if(r<=l || b<=t) return;
            auto c=[&](float xx,float yy){return alpha(palette(horizontal?xx/w:(base-yy)/area),opacity);};
            // Split at palette stops so tall bars retain the exact flame ramp.
            if(!horizontal && (fire || flag("middleEnabled")) && !mono) {
                float stop=base-area*(fire?.25f:.5f);
                if(stop>t && stop<b) {
                    m.quad({l,t},{r,t},{r,stop},{l,stop},c(l,t),c(r,t),c(r,stop),c(l,stop));
                    t=stop;
                }
            }
            if(horizontal && !fire && !mono && flag("middleEnabled") && l<w*.5f && r>w*.5f) {
                float stop=w*.5f;
                m.quad({l,t},{stop,t},{stop,b},{l,b},c(l,t),c(stop,t),c(stop,b),c(l,b));
                l=stop;
            }
            m.quad({l,t},{r,t},{r,b},{l,b},c(l,t),c(r,t),c(r,b),c(l,b));
        };
        if(flag("wash")) for(int i=0;i<n;++i) {
            float v=unit(m_bars[i].toFloat());
            rect(i*w/n,base-v*area,w/n,v*area,.10f);
        }
        for(int i=0;i<n;++i) {
            float v=unit(m_bars[i].toFloat()), bh=std::max(pixel,v*area);
            float x=std::round(i*(bw+gap)*dpr)/dpr;
            float right=std::round((i*(bw+gap)+bw)*dpr)/dpr;
            float y=base-bh;
            if(stacks) {
                float scale=std::max(1.f,number("stackScale",1));
                for(float sy=base;sy>y;sy-=4*scale) {
                    float sh=std::min(3*scale,sy-y); rect(x,sy-sh,right-x,sh);
                }
            } else if(spikes) {
                float tip=std::min(bh,std::min(bw*.8f,6.f));
                rect(x,y+tip,right-x,bh-tip);
                m.vertex(x,y+tip,palette((base-y-tip)/area));
                m.vertex(right,y+tip,palette((base-y-tip)/area));
                m.vertex((x+right)/2,y,palette((base-y)/area));
            } else rect(x,y,right-x,bh);
            if(flag("peaks") && i<m_peaks.size() && m_peaks[i].toFloat()>=.02f) {
                float py=std::max(0.f,base-unit(m_peaks[i].toFloat())*area-pixel);
                QColor cap=mono?flat:(spikes?QColor("#ffe9a8"):QColor(Qt::white));
                m.rect(x,py,right-x,spikes?pixel:2*pixel,cap,cap);
            }
            if(reflect) {
                QColor c=alpha(palette(fire?.12f:0),.22f);
                m.rect(x,base+2,right-x,std::min(v*area*.5f,std::max(0.f,h-base-2)),c,c);
            }
        }
    }
    // Do not retain an empty scene-graph node before the first audio frame.
    // On the native GL backend it can stay culled after geometry arrives.
    if(m.vertices.empty()) { delete node; return nullptr; }
    m.upload(); m.buildNs += timer.nsecsElapsed(); ++m.buildFrames; return node;
}
