#include "stringsnode.h"
#include <QSGGeometryNode>
#include <QSGMaterial>
#include <QSGMaterialShader>
#include <QColor>
#include <QElapsedTimer>
#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <cstdio>
#include <vector>

namespace {
float finite(float v,float fallback=0) { return std::isfinite(v)?v:fallback; }
float unit(float v) { return std::clamp(finite(v),0.f,1.f); }
QColor mix(QColor a,QColor b,float t) {
    t=unit(t);
    return QColor::fromRgbF(a.redF()+(b.redF()-a.redF())*t,
                           a.greenF()+(b.greenF()-a.greenF())*t,
                           a.blueF()+(b.blueF()-a.blueF())*t,
                           a.alphaF()+(b.alphaF()-a.alphaF())*t);
}
struct StringVertex {
    float x,y,layer,offset;
    float basis[9]; // previous/current/next fixed carrier, standing mode, taper
    unsigned char r,g,b,a;
};
const QSGGeometry::AttributeSet &attributes() {
    static const QSGGeometry::Attribute attrs[]={
        QSGGeometry::Attribute::create(0,2,QSGGeometry::FloatType,true),
        QSGGeometry::Attribute::create(1,2,QSGGeometry::FloatType),
        QSGGeometry::Attribute::create(2,3,QSGGeometry::FloatType),
        QSGGeometry::Attribute::create(3,3,QSGGeometry::FloatType),
        QSGGeometry::Attribute::create(4,3,QSGGeometry::FloatType),
        QSGGeometry::Attribute::create(5,4,QSGGeometry::UnsignedByteType)
    };
    static const QSGGeometry::AttributeSet set={6,sizeof(StringVertex),attrs};
    return set;
}
class StringsShader : public QSGMaterialShader {
public:
    StringsShader() {
        setShaderFileName(VertexStage,QStringLiteral(":/omaviz/shaders/strings.vert.qsb"));
        setShaderFileName(FragmentStage,QStringLiteral(":/omaviz/shaders/siri.frag.qsb"));
    }
    bool updateUniformData(RenderState &,QSGMaterial *,QSGMaterial *) override;
};
class StringsMaterial : public QSGMaterial {
public:
    float dimensions[4]{}; // width, height, gain, sample count
    std::array<float,224> vibration{};
    std::array<float,64> coefficients{};
    StringsMaterial() { setFlag(Blending); setFlag(RequiresFullMatrix); setFlag(NoBatching); }
    QSGMaterialType *type() const override { static QSGMaterialType type; return &type; }
    QSGMaterialShader *createShader(QSGRendererInterface::RenderMode) const override { return new StringsShader; }
};
bool StringsShader::updateUniformData(RenderState &state,QSGMaterial *material,QSGMaterial *) {
    auto *data=state.uniformData();
    Q_ASSERT(data->size()>=1248);
    if(state.isMatrixDirty()) {
        auto matrix=state.combinedMatrix(); std::memcpy(data->data(),matrix.constData(),64);
    }
    const float opacity=state.opacity();
    const auto *m=static_cast<StringsMaterial *>(material);
    std::memcpy(data->data()+64,&opacity,4);
    std::memcpy(data->data()+68,m->dimensions,16);
    std::memcpy(data->data()+96,m->vibration.data(),896);
    std::memcpy(data->data()+992,m->coefficients.data(),256);
    return true;
}
struct StringsNode : QSGGeometryNode {
    QSGGeometry mesh{attributes(),0,0,QSGGeometry::UnsignedShortType};
    StringsMaterial shader;
    QVariantMap style;
    float width=0,height=0,dpr=0,energy=0;
    int count=0,frames=0,rebuilds=0;
    double lastPhase=0;
    std::array<float,16> rings{};
    std::vector<float> waveSamples,filtered;
    qint64 cpuNs=0;
    StringsNode() {
        mesh.setDrawingMode(QSGGeometry::DrawTriangleStrip);
        mesh.setVertexDataPattern(QSGGeometry::StaticPattern);
        mesh.setIndexDataPattern(QSGGeometry::StaticPattern);
        setGeometry(&mesh); setMaterial(&shader);
    }
    ~StringsNode() override {
        if(qEnvironmentVariableIsSet("OMAVIZ_PROFILE"))
            fprintf(stderr,"strings mean_cpu_ms %.4f frames %d rebuilds %d vertices %d indices %d\n",
                    frames?cpuNs/1e6/frames:0,frames,rebuilds,mesh.vertexCount(),mesh.indexCount());
    }
    void rebuild(const QVariantMap &s,float w,float h,float scale) {
        style=s; width=w; height=h; dpr=scale; ++rebuilds;
        const float pixel=1/std::max(1.f,scale),size=std::clamp(h/360.f,.25f,1.5f);
        count=std::clamp(int(w*scale/4),48,224);
        auto color=[&](const char *key,const char *fallback) {
            QColor c=s.value(key,QColor(fallback)).value<QColor>();
            return c.isValid()?c:QColor(fallback);
        };
        const QColor bottom=color("bottom","#e68e0d"),top=color("top","#f59e0b");
        auto palette=[&](float t) {
            if(s.value("middleEnabled").toBool()) {
                QColor middle=color("middle","#a855f7");
                return t<.5f?mix(bottom,middle,t*2):mix(middle,top,(t-.5f)*2);
            }
            return mix(bottom,top,t);
        };
        const QColor colors[]={QColor("#d8c889"),QColor("#bda76f"),QColor("#b78560"),
                               QColor("#e6d7ad"),QColor("#c49a73"),QColor("#aebcbe")};
        std::vector<StringVertex> vertices;
        std::vector<quint16> indices;
        vertices.reserve(16*count*6); indices.reserve(16*(count-1)*14);
        for(int layer=0;layer<16;++layer) {
            if(h<48 && layer%2) continue;
            const bool foreground=layer>=13,distant=!foreground && layer%4==0,glow=h>=48;
            const float frequency=foreground?(.65f+(layer-13)*.38f):(2.1f+(layer%7)*.46f);
            const float halfWidth=(foreground?1.55f:.65f)*size
                *std::clamp(finite(s.value("lineWidth",2).toFloat(),2)/2.f,.5f,2.5f);
            const float opacity=foreground?.32f:(distant?.34f:.72f);
            const float feather=std::max(pixel,(foreground?3.3f:(distant?2.3f:1.1f))*size);
            const float halo=(foreground?14.f:(distant?9.f:4.5f))*size;
            const float bloom=(foreground?6.f:(distant?4.f:2.f))*size;
            const int levels=glow?3:2,edges=levels*2;
            const float distances[]={0,feather,std::max(feather+.001f,halo)};
            QColor tint=s.value("mono").toBool()?(s.value("monoLight").toBool()?Qt::black:Qt::white)
                :s.value("custom").toBool()?palette(float(layer)/15):colors[foreground?5:layer%5];
            QRgb colorsAtEdge[3];
            for(int j=0;j<levels;++j) {
                const float d=distances[j];
                float core=opacity*std::max(0.f,1-d/feather);
                float inner=glow?.16f*std::max(0.f,1-d/std::max(.001f,bloom)):0;
                float outer=glow?.07f*std::max(0.f,1-d/std::max(.001f,halo)):0;
                QColor c=tint; c.setAlphaF(unit(c.alphaF()*(1-(1-core)*(1-inner)*(1-outer))));
                colorsAtEdge[j]=qPremultiply(c.rgba());
            }
            for(int i=0;i<count;++i) {
                StringVertex v{};
                v.x=float(i)/(count-1)*w;
                v.layer=float(layer);
                for(int neighbor=0;neighbor<3;++neighbor) {
                    const float x=float(std::clamp(i+neighbor-1,0,count-1))/(count-1);
                    v.basis[neighbor*3]=std::sin(x*6.2831853f*frequency+layer*.83f);
                    v.basis[neighbor*3+1]=std::sin(x*3.14159265f*(1+layer%3));
                    v.basis[neighbor*3+2]=std::sin(x*3.14159265f);
                }
                const int start=int(vertices.size());
                for(int edge=0;edge<edges;++edge) {
                    const int level=edge<levels?levels-1-edge:edge-levels;
                    v.offset=(halfWidth+distances[level])*(edge<levels?1.f:-1.f);
                    v.y=edge<levels?0.f:h; // Conservative bounds for culling.
                    QRgb c=colorsAtEdge[level]; v.r=qRed(c);v.g=qGreen(c);v.b=qBlue(c);v.a=qAlpha(c);
                    vertices.push_back(v);
                }
                if(i) {
                    if(!indices.empty()) { indices.push_back(indices.back()); indices.push_back(quint16(start-edges)); }
                    for(int j=0;j<edges;++j) {
                        indices.push_back(quint16(start-edges+j)); indices.push_back(quint16(start+j));
                    }
                }
            }
        }
        mesh.allocate(int(vertices.size()),int(indices.size()));
        std::memcpy(mesh.vertexData(),vertices.data(),vertices.size()*sizeof(StringVertex));
        std::memcpy(mesh.indexDataAsUShort(),indices.data(),indices.size()*sizeof(quint16));
        mesh.markVertexDataDirty(); mesh.markIndexDataDirty(); markDirty(DirtyGeometry);
        shader.dimensions[0]=w;shader.dimensions[1]=h;
        shader.dimensions[2]=std::clamp(finite(style.value("gain",1).toFloat(),1),.1f,4.f);
        shader.dimensions[3]=float(count);
    }
    void update(const QVariantList &bands,const QVariantList &wave,double phase) {
        const int n=int(wave.size());
        waveSamples.resize(n); filtered.resize(n);
        float rms=0;
        for(int i=0;i<n;++i) { float v=finite(wave[i].toFloat());waveSamples[i]=v;rms+=v*v; }
        rms=std::sqrt(rms/std::max(1,n));
        const float dt=std::clamp(phase-lastPhase,0.,.1);
        energy+=(rms-energy)*(1-std::exp(-dt*5));lastPhase=phase;
        const float amplitude=std::sqrt(unit((energy-.001f)*5.f));
        shader.vibration.fill(0);
        if(n>4) {
            for(int i=0;i<n;++i) {
                float sum=0;
                for(int tap=-4;tap<=4;++tap) sum+=waveSamples[std::clamp(i+tap,0,n-1)];
                filtered[i]=sum/9.f;
            }
            for(int i=0;i<count;++i) {
                const float position=float(i)/(count-1)*(n-1);
                int lo=int(position),hi=std::min(lo+1,n-1);
                shader.vibration[i]=filtered[lo]+(filtered[hi]-filtered[lo])*(position-lo);
            }
        }
        for(int layer=0;layer<16;++layer) {
            if(height<48 && layer%2) continue;
            const bool foreground=layer>=13;
            float drive=0;
            if(style.value("compactStrings").toBool() && bands.size()==16) {
                drive=unit(bands[layer].toFloat());
            } else if(!bands.empty()) {
                const int band=std::clamp(int((layer+.5f)/16*bands.size()),0,int(bands.size())-1);
                for(int tap=-2;tap<=2;++tap) drive=std::max(drive,unit(bands[std::clamp(band+tap,0,int(bands.size())-1)].toFloat()));
            }
            drive=std::sqrt(drive);
            if(foreground) drive=std::max(drive,amplitude*.8f);
            auto &ring=rings[layer];ring+=(drive-ring)*(1-std::exp(-dt*(drive>ring?22.f:3.8f)));
            const float extent=(.39f+.09f*std::sin(layer*2.1f))*std::clamp(amplitude*.35f+ring*.85f,0.f,1.f);
            const float vibrationPhase=phase*(7.5f+layer*.68f)+layer*.47f;
            shader.coefficients[layer*4]=extent*(.35f+.65f*std::sin(vibrationPhase));
            shader.coefficients[layer*4+1]=ring*.14f*std::sin(vibrationPhase*.71f+layer);
            shader.coefficients[layer*4+2]=(amplitude*.3f+ring*.7f)*(foreground?.11f:.045f);
        }
        markDirty(DirtyMaterial);
    }
};
}
QSGNode *updateStringsNode(QSGNode *old,const QVariantMap &style,const QVariantList &bands,
                          const QVariantList &wave,double phase,float width,float height,float dpr) {
    if(width<=0 || height<=0) { delete old;return nullptr; }
    auto *node=static_cast<StringsNode *>(old);
    if(!node) node=new StringsNode;
    QElapsedTimer timer;timer.start();
    if(node->style!=style || node->width!=width || node->height!=height || node->dpr!=dpr)
        node->rebuild(style,width,height,dpr);
    node->update(bands,wave,phase);node->cpuNs+=timer.nsecsElapsed();++node->frames;
    return node;
}
