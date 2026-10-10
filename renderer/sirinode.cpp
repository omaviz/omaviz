#include "sirinode.h"
#include "siriresponse.h"
#include <QSGGeometryNode>
#include <QSGMaterial>
#include <QSGMaterialShader>
#include <QSGVertexColorMaterial>
#include <QColor>
#include <QElapsedTimer>
#include <algorithm>
#include <cmath>
#include <cstring>
#include <cstdio>
#include <vector>

namespace {
float finite(float v) { return std::isfinite(v)?v:0.f; }
QColor mix(QColor a,QColor b,float t) {
    return QColor::fromRgbF(a.redF()+(b.redF()-a.redF())*t,a.greenF()+(b.greenF()-a.greenF())*t,
        a.blueF()+(b.blueF()-a.blueF())*t,a.alphaF()+(b.alphaF()-a.alphaF())*t);
}
struct SiriVertex { float x,y,layer,edge,unused; unsigned char r,g,b,a; };
const QSGGeometry::AttributeSet &attributes() {
    static const QSGGeometry::Attribute a[]={
        QSGGeometry::Attribute::create(0,2,QSGGeometry::FloatType,true),
        QSGGeometry::Attribute::create(1,3,QSGGeometry::FloatType),
        QSGGeometry::Attribute::create(2,4,QSGGeometry::UnsignedByteType)};
    static const QSGGeometry::AttributeSet set={3,sizeof(SiriVertex),a}; return set;
}
class SiriShader : public QSGMaterialShader {
public:
    SiriShader() {
        setShaderFileName(VertexStage,QStringLiteral(":/omaviz/shaders/siri.vert.qsb"));
        setShaderFileName(FragmentStage,QStringLiteral(":/omaviz/shaders/siri.frag.qsb"));
        setFlag(UpdatesGraphicsPipelineState);
    }
    bool updateUniformData(RenderState &,QSGMaterial *,QSGMaterial *) override;
    bool updateGraphicsPipelineState(RenderState &,GraphicsPipelineState *,QSGMaterial *,QSGMaterial *) override;
};
class SiriMaterial : public QSGMaterial {
public:
    float dimensions[3]{};
    std::array<SiriResponse::Lobe,6> lobes{};
    float options[4]{};
    bool additive=true;
    SiriMaterial() { setFlag(Blending);setFlag(RequiresFullMatrix);setFlag(NoBatching); }
    QSGMaterialType *type() const override { static QSGMaterialType type;return &type; }
    QSGMaterialShader *createShader(QSGRendererInterface::RenderMode) const override { return new SiriShader; }
};
bool SiriShader::updateUniformData(RenderState &state,QSGMaterial *material,QSGMaterial *) {
    auto *data=state.uniformData(); Q_ASSERT(data->size()>=192);
    if(state.isMatrixDirty())std::memcpy(data->data(),state.combinedMatrix().constData(),64);
    const float opacity=state.opacity();std::memcpy(data->data()+64,&opacity,4);
    auto *m=static_cast<SiriMaterial *>(material);
    std::memcpy(data->data()+68,m->dimensions,12);
    static_assert(sizeof(SiriResponse::Lobe)==16);
    std::memcpy(data->data()+80,m->lobes.data(),96);
    std::memcpy(data->data()+176,m->options,16);
    return true;
}
bool SiriShader::updateGraphicsPipelineState(RenderState &,GraphicsPipelineState *ps,QSGMaterial *material,QSGMaterial *) {
    auto *m=static_cast<SiriMaterial *>(material);
    ps->srcColor=GraphicsPipelineState::One;
    ps->dstColor=m->additive?GraphicsPipelineState::One:GraphicsPipelineState::OneMinusSrcAlpha;
    // Keep alpha compositable while light from colored lobes adds toward white.
    ps->separateBlendFactors=true;
    ps->srcAlpha=GraphicsPipelineState::One;ps->dstAlpha=GraphicsPipelineState::OneMinusSrcAlpha;
    return true;
}
struct SiriNode : QSGGeometryNode {
    QSGGeometry mesh{attributes(),0,0,QSGGeometry::UnsignedShortType};
    SiriMaterial shader;
    QSGGeometry axis{QSGGeometry::defaultAttributes_ColoredPoint2D(),12,36,QSGGeometry::UnsignedShortType};
    QSGVertexColorMaterial axisMaterial;
    QSGGeometryNode *axisNode=new QSGGeometryNode;
    QVariantMap style;
    std::vector<SiriVertex> source;
    float width=0,height=0,dpr=0;
    SiriResponse response;
    double lastPhase=0;
    qint64 cpuNs=0;int frames=0,rebuilds=0;
    const bool cpu=qEnvironmentVariableIsSet("OMAVIZ_SIRI_LEGACY");
    SiriNode() {
        mesh.setDrawingMode(QSGGeometry::DrawTriangles);
        mesh.setVertexDataPattern(cpu?QSGGeometry::DynamicPattern:QSGGeometry::StaticPattern);
        mesh.setIndexDataPattern(QSGGeometry::StaticPattern);
        setGeometry(&mesh);setMaterial(&shader);
        axis.setDrawingMode(QSGGeometry::DrawTriangles);
        axis.setVertexDataPattern(QSGGeometry::StaticPattern);axis.setIndexDataPattern(QSGGeometry::StaticPattern);
        axisMaterial.setFlag(QSGMaterial::Blending);
        axisNode->setGeometry(&axis);axisNode->setMaterial(&axisMaterial);appendChildNode(axisNode);
    }
    ~SiriNode() override {
        removeChildNode(axisNode);delete axisNode;
        if(qEnvironmentVariableIsSet("OMAVIZ_PROFILE"))fprintf(stderr,
            "siri %s mean_cpu_ms %.4f frames %d rebuilds %d vertices %d indices %d\n",
            cpu?"cpu":"retained",frames?cpuNs/1e6/frames:0,frames,rebuilds,mesh.vertexCount(),mesh.indexCount());
    }
    void rebuild(const QVariantMap &s,float w,float h,float scale) {
        style=s;width=w;height=h;dpr=scale;++rebuilds;
        const float pixel=1/std::max(1.f,dpr);
        const int count=std::clamp(int(w*dpr/12),48,160);
        auto color=[&](const char *key,const char *fallback){QColor c=s.value(key,QColor(fallback)).value<QColor>();return c.isValid()?c:QColor(fallback);};
        const QColor bottom=color("bottom","#e68e0d"),top=color("top","#f59e0b");
        auto palette=[&](float t){
            if(s.value("middleEnabled").toBool()) {
                QColor middle=color("middle","#a855f7");return t<.5f?mix(bottom,middle,t*2):mix(middle,top,(t-.5f)*2);
            }return mix(bottom,top,t);
        };
        const bool mono=s.value("mono").toBool(),custom=s.value("custom").toBool();
        const QColor flat=s.value("monoLight").toBool()?Qt::black:Qt::white;
        const QColor hues[]={QColor("#ff2658"),QColor("#127dff"),QColor("#2dffa0"),
                             QColor("#08d9ff"),QColor("#ff3977"),QColor("#39ef8c")};
        shader.additive=!mono;
        source.clear();std::vector<quint16> indices;
        source.reserve(6*count*5);indices.reserve(6*(count-1)*24);
        for(int layer=0;layer<6;++layer) {
            const QColor tint=mono?flat:custom?palette(float(layer)/5):hues[layer];
            const int start=int(source.size());
            for(int i=0;i<count;++i) {
                const float x=2.f*i/(count-1)-1;
                const float curve=(1-x*x)*(1-x*x);
                const float yy[]={-curve,-curve,0,curve,curve};
                const float edges[]={-1,0,0,0,1};
                const float coverage[]={0,.76f,.96f,.76f,0};
                for(int j=0;j<5;++j) {
                    QColor c=tint;c.setAlphaF(c.alphaF()*coverage[j]);QRgb packed=qPremultiply(c.rgba());
                    source.push_back({(x*.5f+.5f)*w,(yy[j]*.5f+.5f)*h,float(layer),edges[j],0,
                        (unsigned char)qRed(packed),(unsigned char)qGreen(packed),(unsigned char)qBlue(packed),(unsigned char)qAlpha(packed)});
                }
                if(i)for(int j=0;j<4;++j) {
                    int a=start+(i-1)*5+j,b=start+i*5+j;
                    for(int n:{a,b,b+1,a,b+1,a+1})indices.push_back(quint16(n));
                }
            }
        }
        mesh.allocate(int(source.size()),int(indices.size()));
        std::memcpy(mesh.vertexData(),source.data(),source.size()*sizeof(SiriVertex));
        std::memcpy(mesh.indexDataAsUShort(),indices.data(),indices.size()*sizeof(quint16));
        mesh.markVertexDataDirty();mesh.markIndexDataDirty();markDirty(DirtyGeometry);
        shader.dimensions[0]=w;shader.dimensions[1]=h;shader.dimensions[2]=pixel;shader.options[0]=cpu?1:0;
        auto *v=axis.vertexDataAsColoredPoint2D();auto *idx=axis.indexDataAsUShort();int k=0;
        const QColor axisTint=mono?flat:QColor("#ebeff2");
        for(int i=0;i<3;++i) {
            const float offsets[]={1.15f,.15f,-.15f,-1.15f};
            for(int j=0;j<4;++j) {
                QColor c=axisTint;c.setAlphaF(i==1 && (j==1||j==2)?.48f:0.f);QRgb p=qPremultiply(c.rgba());
                v[i*4+j].set((.08f+.42f*i)*w,h*.5f+offsets[j]*pixel,qRed(p),qGreen(p),qBlue(p),qAlpha(p));
            }
            if(i)for(int j=0;j<3;++j) {int a=(i-1)*4+j,b=i*4+j;for(int n:{a,b,b+1,a,b+1,a+1})idx[k++]=quint16(n);}
        }
        axis.markVertexDataDirty();axis.markIndexDataDirty();axisNode->markDirty(DirtyGeometry);
    }
    void update(const QVariantList &bands,const QVariantList &wave,double phase) {
        float rms=0;for(const auto &sample:wave){float v=finite(sample.toFloat());rms+=v*v;}
        rms=std::sqrt(rms/std::max(1,int(wave.size())));
        const float gain=std::clamp(finite(style.value("gain",1).toFloat()),.1f,4.f);
        std::array<float,6> drives{};
        const bool compact=style.value("compactSiri",false).toBool() && bands.size()==6;
        if(compact)for(int i=0;i<6;++i)drives[i]=finite(bands[i].toFloat());
        response.step(rms,gain,std::clamp(float(phase-lastPhase),0.f,.1f),compact?&drives:nullptr);lastPhase=phase;
        for(int i=0;i<6;++i)shader.lobes[i]=response.lobe(i,height,style.value("siriTravel",false).toBool());
        if(cpu) {
            auto *v=static_cast<SiriVertex *>(mesh.vertexData());
            for(size_t i=0;i<source.size();++i) {
                v[i]=source[i];const auto &l=shader.lobes[int(v[i].layer)];
                v[i].x=(l.center+(2*v[i].x/width-1)*l.radius)*width;
                v[i].y=height*(.5f+(2*v[i].y/height-1)*l.height)+v[i].edge*shader.dimensions[2];
            }
            mesh.markVertexDataDirty();markDirty(DirtyGeometry);
        }
        markDirty(DirtyMaterial);
    }
};
}
QSGNode *updateSiriNode(QSGNode *old,const QVariantMap &style,const QVariantList &bands,const QVariantList &wave,
                       double phase,float width,float height,float dpr) {
    if(width<=0||height<=0){delete old;return nullptr;}
    auto *node=static_cast<SiriNode *>(old);if(!node)node=new SiriNode;
    QElapsedTimer timer;timer.start();
    if(node->style!=style||node->width!=width||node->height!=height||node->dpr!=dpr)node->rebuild(style,width,height,dpr);
    node->update(bands,wave,phase);node->cpuNs+=timer.nsecsElapsed();++node->frames;return node;
}
