#include "siriribbonnode.h"
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

// Existing ribbon renderer retained unchanged in appearance and response.
namespace {
float finite(float v){return std::isfinite(v)?v:0.f;}
float unit(float v){return std::clamp(finite(v),0.f,1.f);}
QColor alpha(QColor c,float a){c.setAlphaF(unit(c.alphaF()*a));return c;}
QColor mix(QColor a,QColor b,float t){t=unit(t);return QColor::fromRgbF(a.redF()+(b.redF()-a.redF())*t,
    a.greenF()+(b.greenF()-a.greenF())*t,a.blueF()+(b.blueF()-a.blueF())*t,a.alphaF()+(b.alphaF()-a.alphaF())*t);}
struct Vertex{float x,y,layer,kind,offset;unsigned char r,g,b,a;};
const QSGGeometry::AttributeSet &attributes(){
    static const QSGGeometry::Attribute a[]={QSGGeometry::Attribute::create(0,2,QSGGeometry::FloatType,true),
        QSGGeometry::Attribute::create(1,3,QSGGeometry::FloatType),QSGGeometry::Attribute::create(2,4,QSGGeometry::UnsignedByteType)};
    static const QSGGeometry::AttributeSet set={3,sizeof(Vertex),a};return set;
}
class Shader:public QSGMaterialShader{
public:
    Shader(){setShaderFileName(VertexStage,QStringLiteral(":/omaviz/shaders/siri-ribbon.vert.qsb"));
        setShaderFileName(FragmentStage,QStringLiteral(":/omaviz/shaders/siri.frag.qsb"));}
    bool updateUniformData(RenderState &,QSGMaterial *,QSGMaterial *) override;
};
class Material:public QSGMaterial{
public:
    float values[7]{},levels[8]{};
    Material(){setFlag(Blending);setFlag(RequiresFullMatrix);setFlag(NoBatching);}
    QSGMaterialType *type()const override{static QSGMaterialType type;return &type;}
    QSGMaterialShader *createShader(QSGRendererInterface::RenderMode)const override{return new Shader;}
};
bool Shader::updateUniformData(RenderState &state,QSGMaterial *material,QSGMaterial *){
    auto *data=state.uniformData();Q_ASSERT(data->size()>=128);
    if(state.isMatrixDirty())std::memcpy(data->data(),state.combinedMatrix().constData(),64);
    float opacity=state.opacity();std::memcpy(data->data()+64,&opacity,4);
    auto *m=static_cast<Material *>(material);std::memcpy(data->data()+68,m->values,28);std::memcpy(data->data()+96,m->levels,32);return true;
}
struct RibbonNode:QSGGeometryNode{
    QSGGeometry mesh{attributes(),0,0,QSGGeometry::UnsignedShortType};Material shader;
    QSGGeometry axis{QSGGeometry::defaultAttributes_ColoredPoint2D(),12,36,QSGGeometry::UnsignedShortType};
    QSGVertexColorMaterial axisMaterial;QSGGeometryNode *axisNode=new QSGGeometryNode;
    QVariantMap style;float width=0,height=0,dpr=0;SiriResponse response;double lastPhase=0;
    QColor axisLeft,axisRight;qint64 cpuNs=0;int frames=0,rebuilds=0;
    RibbonNode(){
        mesh.setDrawingMode(QSGGeometry::DrawTriangleStrip);mesh.setVertexDataPattern(QSGGeometry::StaticPattern);mesh.setIndexDataPattern(QSGGeometry::StaticPattern);
        setGeometry(&mesh);setMaterial(&shader);axis.setDrawingMode(QSGGeometry::DrawTriangles);
        axis.setVertexDataPattern(QSGGeometry::DynamicPattern);axis.setIndexDataPattern(QSGGeometry::StaticPattern);
        axisMaterial.setFlag(QSGMaterial::Blending);axisNode->setGeometry(&axis);axisNode->setMaterial(&axisMaterial);appendChildNode(axisNode);
    }
    ~RibbonNode()override{removeChildNode(axisNode);delete axisNode;
        if(qEnvironmentVariableIsSet("OMAVIZ_PROFILE"))fprintf(stderr,"siri ribbons mean_cpu_ms %.4f frames %d rebuilds %d vertices %d indices %d\n",
            frames?cpuNs/1e6/frames:0,frames,rebuilds,mesh.vertexCount(),mesh.indexCount());}
    void rebuild(const QVariantMap &s,float w,float h,float scale){
        style=s;width=w;height=h;dpr=scale;++rebuilds;const float pixel=1/std::max(1.f,dpr);
        const int count=std::clamp(int(w*dpr/5),64,240);
        auto color=[&](const char *key,const char *fallback){QColor c=s.value(key,QColor(fallback)).value<QColor>();return c.isValid()?c:QColor(fallback);};
        const QColor bottom=color("bottom","#e68e0d"),top=color("top","#f59e0b");
        auto palette=[&](float t){if(s.value("middleEnabled").toBool()){QColor middle=color("middle","#a855f7");
            return t<.5f?mix(bottom,middle,t*2):mix(middle,top,(t-.5f)*2);}return mix(bottom,top,t);};
        const bool mono=s.value("mono").toBool(),custom=s.value("custom").toBool();
        const QColor flat=s.value("monoLight").toBool()?Qt::black:Qt::white;
        const QColor hues[]={QColor("#ba32dd"),QColor("#4936ca"),QColor("#087dda"),QColor("#00bde8"),QColor("#36ceef"),QColor("#acdfff")};
        std::vector<Vertex> vertices;std::vector<quint16> indices;vertices.reserve(6*count*15);indices.reserve(6*(count-1)*72);
        auto vertex=[&](float x,int layer,int kind,float offset,QColor color){QRgb c=qPremultiply(color.rgba());
            vertices.push_back({x*w,kind==0?0.f:h,float(layer),float(kind),offset,(unsigned char)qRed(c),(unsigned char)qGreen(c),(unsigned char)qBlue(c),(unsigned char)qAlpha(c)});};
        auto beginStrip=[&](int first){if(!indices.empty()){indices.push_back(indices.back());indices.push_back(quint16(first));}};
        auto ribbon=[&](int layer,int kind,QColor tint){
            const bool glow=kind==0;const int levels=glow?4:2,edges=levels*2,start=int(vertices.size());
            const float halfWidth=(glow?.45f:.4f)*pixel,halo=std::min(h*.035f,5.f)*pixel,bloom=pixel;
            float distance[]={0.f,pixel,pixel,std::max(pixel+.001f,halo)},coverage[4]{};
            for(int j=0;j<levels;++j){const float d=distance[j];float core=(glow?.24f:.18f)*std::max(0.f,1-d/pixel);
                float inner=glow?.16f*std::max(0.f,1-d/std::max(.001f,bloom)):0;
                float outer=glow?.07f*std::max(0.f,1-d/std::max(.001f,halo)):0;coverage[j]=1-(1-core)*(1-inner)*(1-outer);}
            for(int i=0;i<count;++i){float x=float(i)/(count-1);
                for(int j=levels-1;j>=0;--j)vertex(x,layer,kind,halfWidth+distance[j],alpha(tint,coverage[j]));
                for(int j=0;j<levels;++j)vertex(x,layer,kind,-halfWidth-distance[j],alpha(tint,coverage[j]));
                if(i){beginStrip(start+i*edges);for(int j=0;j<edges;++j){indices.push_back(quint16(start+i*edges+j));indices.push_back(quint16(start+(i-1)*edges+j));}}
            }
        };
        for(int layer=0;layer<6;++layer){QColor tint=mono?flat:custom?palette(float(layer)/5):hues[layer];const int start=int(vertices.size());
            for(int i=0;i<count;++i){const float x=float(i)/(count-1),a=std::pow(std::max(0.f,std::sin(x*3.14159265f)),1.2f);
                vertex(x,layer,0,0,alpha(tint,.48f*a));vertex(x,layer,1,0,alpha(tint,(layer==5?.22f:.46f)*a));vertex(x,layer,2,0,alpha(tint,.48f*a));}
            beginStrip(start+1);for(int i=0;i<count;++i){indices.push_back(quint16(start+i*3+1));indices.push_back(quint16(start+i*3));}
            beginStrip(start+2);for(int i=0;i<count;++i){indices.push_back(quint16(start+i*3+2));indices.push_back(quint16(start+i*3+1));}
            ribbon(layer,0,tint);ribbon(layer,2,tint);
        }
        mesh.allocate(int(vertices.size()),int(indices.size()));std::memcpy(mesh.vertexData(),vertices.data(),vertices.size()*sizeof(Vertex));
        std::memcpy(mesh.indexDataAsUShort(),indices.data(),indices.size()*sizeof(quint16));mesh.markVertexDataDirty();mesh.markIndexDataDirty();markDirty(DirtyGeometry);
        shader.values[0]=w;shader.values[1]=h;shader.values[4]=pixel;shader.values[5]=1.f/(count-1);
        axisLeft=mono?flat:custom?palette(0):QColor("#a8e7ff");axisRight=mono?flat:custom?palette(1):QColor("#cdefff");
        auto *v=axis.vertexDataAsColoredPoint2D();auto *idx=axis.indexDataAsUShort();int k=0;
        for(int i=0;i<3;++i){const float offsets[]={1.22f,.22f,-.22f,-1.22f};for(int j=0;j<4;++j)v[i*4+j].set(i*w*.5f,h*.5f+offsets[j]*pixel,0,0,0,0);
            if(i)for(int j=0;j<3;++j){int a=(i-1)*4+j,b=i*4+j;for(int n:{a,b,b+1,a,b+1,a+1})idx[k++]=quint16(n);}}
        axis.markIndexDataDirty();
    }
    void update(const QVariantList &bands,const QVariantList &wave,double phase){
        float rms=0;for(const auto &sample:wave){float v=finite(sample.toFloat());rms+=v*v;}rms=std::sqrt(rms/std::max(1,int(wave.size())));
        const float gain=std::clamp(finite(style.value("gain",1).toFloat()),.1f,4.f);std::array<float,6> drives{};
        const bool compact=style.value("compactSiri",false).toBool()&&bands.size()==6;if(compact)for(int i=0;i<6;++i)drives[i]=finite(bands[i].toFloat());
        response.step(rms,gain,std::clamp(float(phase-lastPhase),0.f,.1f),compact?&drives:nullptr,true);lastPhase=phase;
        shader.values[2]=response.motion;shader.values[3]=SiriResponse::visible(response.energy,height);shader.values[6]=response.pulse;
        for(int i=0;i<6;++i)shader.levels[i]=SiriResponse::visible(response.layers[i],height);
        shader.levels[6]=style.value("siriTravel",false).toBool()?1.f:0.f;markDirty(DirtyMaterial);
        auto *v=axis.vertexDataAsColoredPoint2D();for(int i=0;i<3;++i){QColor tint=mix(axisLeft,axisRight,i*.5f);for(int j=0;j<4;++j){
            const float coverage=(j==1||j==2)?1-(1-(.10f+.12f*response.energy)):0;QRgb c=qPremultiply(alpha(tint,coverage).rgba());
            auto &p=v[i*4+j];p.r=qRed(c);p.g=qGreen(c);p.b=qBlue(c);p.a=qAlpha(c);}}
        axis.markVertexDataDirty();axisNode->markDirty(DirtyGeometry);
    }
};
}
QSGNode *updateSiriRibbonNode(QSGNode *old,const QVariantMap &style,const QVariantList &bands,const QVariantList &wave,
                            double phase,float width,float height,float dpr){
    if(width<=0||height<=0){delete old;return nullptr;}auto *node=static_cast<RibbonNode *>(old);if(!node)node=new RibbonNode;
    QElapsedTimer timer;timer.start();if(node->style!=style||node->width!=width||node->height!=height||node->dpr!=dpr)node->rebuild(style,width,height,dpr);
    node->update(bands,wave,phase);node->cpuNs+=timer.nsecsElapsed();++node->frames;return node;
}
