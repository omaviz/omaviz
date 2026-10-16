#include "ambientnode.h"
#include "ambientresponse.h"
#include <QSGGeometryNode>
#include <QSGMaterial>
#include <QSGMaterialShader>
#include <QElapsedTimer>
#include <QColor>
#include <array>
#include <cstring>
#include <cstdio>
#include <vector>

namespace {
struct Vertex { float x,y,id,row,kind,unused,sx,sy,sz; };
const QSGGeometry::AttributeSet &attributes() {
    static const QSGGeometry::Attribute attrs[]={
        QSGGeometry::Attribute::create(0,2,QSGGeometry::FloatType,true),
        QSGGeometry::Attribute::create(1,4,QSGGeometry::FloatType),
        QSGGeometry::Attribute::create(2,3,QSGGeometry::FloatType)};
    static const QSGGeometry::AttributeSet set={3,sizeof(Vertex),attrs}; return set;
}
class Shader:public QSGMaterialShader {
public:
    Shader() {
        setShaderFileName(VertexStage,QStringLiteral(":/omaviz/shaders/ambient.vert.qsb"));
        setShaderFileName(FragmentStage,QStringLiteral(":/omaviz/shaders/ambient.frag.qsb"));
    }
    bool updateUniformData(RenderState &,QSGMaterial *,QSGMaterial *) override;
};
class Material:public QSGMaterial {
public:
    std::array<float,28> params{};
    std::array<float,24> levels{};
    std::array<float,640> history{};
    Material() { setFlag(Blending);setFlag(RequiresFullMatrix);setFlag(NoBatching); }
    QSGMaterialType *type() const override { static QSGMaterialType type;return &type; }
    QSGMaterialShader *createShader(QSGRendererInterface::RenderMode) const override { return new Shader; }
};
bool Shader::updateUniformData(RenderState &state,QSGMaterial *material,QSGMaterial *) {
    auto *data=state.uniformData();Q_ASSERT(data->size()>=2832);
    if(state.isMatrixDirty()) { auto matrix=state.combinedMatrix();std::memcpy(data->data(),matrix.constData(),64); }
    auto *m=static_cast<Material *>(material);m->params[0]=state.opacity();
    std::memcpy(data->data()+64,m->params.data(),112);
    std::memcpy(data->data()+176,m->levels.data(),96);
    std::memcpy(data->data()+272,m->history.data(),2560);return true;
}
float seed(int i,int salt) {
    unsigned n=unsigned(i+1)*747796405u+unsigned(salt)*2891336453u;
    n=(n^(n>>16))*2246822519u;n=(n^(n>>13))*3266489917u;
    return float((n^(n>>16))&65535u)/65535;
}
struct Node:QSGGeometryNode {
    QSGGeometry mesh{attributes(),0};Material shader;AmbientResponse response;
    QString mode;float width=0,height=0,dpr=0;int count=0,rows=0,frames=0,rebuilds=0;
    double lastPhase=0;qint64 cpuNs=0;
    Node() {
        mesh.setDrawingMode(QSGGeometry::DrawTriangles);mesh.setVertexDataPattern(QSGGeometry::StaticPattern);
        setGeometry(&mesh);setMaterial(&shader);
    }
    ~Node() override {
        if(qEnvironmentVariableIsSet("OMAVIZ_PROFILE"))
            fprintf(stderr,"ambient %s mean_cpu_ms %.4f frames %d rebuilds %d vertices %d\n",
                    qPrintable(mode),frames?cpuNs/1e6/frames:0,frames,rebuilds,mesh.vertexCount());
    }
    void rebuild(QString visual,float w,float h,float scale) {
        if(mode!=visual) { response={};lastPhase=0; }
        mode=visual;width=w;height=h;dpr=scale;++rebuilds;
        bool compact=h<48;
        count=mode=="Orbit"?(compact?4:10):mode=="Bokeh"?(compact?16:64):compact?12:std::clamp(int(w/h*12),16,40);
        rows=mode=="PixelWave"?(compact?4:AmbientResponse::Rows):1;
        std::vector<Vertex> vertices;
        auto quad=[&](float left,float top,float right,float bottom,int id,int row,int kind) {
            float z=seed(id,3)*2-1,angle=seed(id,7)*6.2831853f,radius=std::pow(seed(id,11),.55f);
            float xy=std::sqrt(std::max(0.f,1-z*z))*radius;
            for(int corner:{0,1,2,0,2,3}) {
                float x=corner==1||corner==2?right:left,y=corner>=2?bottom:top;
                // Keep native bounds equal to the item's viewport, even though
                // the shader positions the retained normalized primitives.
                vertices.push_back({(x+1)*w*.5f,(y+1)*h*.5f,float(id),float(row),float(kind),0,
                                    std::cos(angle)*xy,std::sin(angle)*xy,z*radius});
            }
        };
        for(int row=rows-1;row>=0;--row) for(int i=0;i<count;++i) {
            if(mode=="Orbit") {
                constexpr int segments=64;
                for(int j=0;j<segments;++j) quad(float(j)/segments*2-1,-1,float(j+1)/segments*2-1,1,i,0,0);
                quad(-1,-1,1,1,i,0,1);quad(-1,-1,1,1,i,0,2);
            } else quad(-1,-1,1,1,i,row,0);
        }
        mesh.allocate(int(vertices.size()));std::memcpy(mesh.vertexData(),vertices.data(),vertices.size()*sizeof(Vertex));
        mesh.markVertexDataDirty();markDirty(DirtyGeometry);
    }
};
}
QSGNode *updateAmbientNode(QSGNode *old,const QVariantMap &style,const QVariantList &bands,
                           const QVariantList &wave,double phase,float w,float h,float dpr) {
    if(w<=0||h<=0) { delete old;return nullptr; }
    QElapsedTimer timer;timer.start();
    auto *node=static_cast<Node *>(old);if(!node)node=new Node;
    const QString mode=style.value("mode").toString();
    if(node->mode!=mode||node->width!=w||node->height!=h||node->dpr!=dpr)node->rebuild(mode,w,h,dpr);
    std::array<float,AmbientResponse::Bands> input{};
    for(int i=0;i<AmbientResponse::Bands;++i) {
        int lo=i*bands.size()/AmbientResponse::Bands,hi=std::max(lo+1,int((i+1)*bands.size()/AmbientResponse::Bands));
        for(int j=lo;j<hi && j<bands.size();++j)input[i]=std::max(input[i],AmbientResponse::unit(bands[j].toFloat()));
    }
    std::array<float,AmbientResponse::Columns> trace{};float peak=.005f;
    for(const auto &sample:wave) { float v=sample.toFloat();if(std::isfinite(v))peak=std::max(peak,std::abs(v)); }
    for(int i=0;i<AmbientResponse::Columns;++i) {
        int lo=i*wave.size()/AmbientResponse::Columns,hi=std::max(lo+1,int((i+1)*wave.size()/AmbientResponse::Columns));
        int n=0;for(int j=lo;j<hi && j<wave.size();++j) {
            float v=wave[j].toFloat();if(std::isfinite(v))trace[i]+=std::clamp(v/peak,-1.f,1.f);++n;
        }
        if(n)trace[i]/=n;
    }
    float dt=std::isfinite(phase)?float(std::clamp(phase-node->lastPhase,0.,.1)):0;
    if(std::isfinite(phase))node->lastPhase=phase;
    node->response.step(input,trace,style.value("gain",1).toFloat(),dt);
    auto &p=node->shader.params;const auto &r=node->response;
    p[1]=w;p[2]=h;p[3]=1/std::max(1.f,dpr);
    // Reducing the uniform clock keeps trigonometry precise in long sessions.
    p[4]=float(std::fmod(r.motion,1000*6.283185307179586));p[5]=r.energy;p[6]=r.pulse;
    p[7]=mode=="Orbit"?0:mode=="PixelWave"?1:2;
    p[8]=node->count;p[9]=node->rows;p[10]=h<48;p[11]=0;
    const bool mono=style.value("mono").toBool();
    p[12]=mono;p[13]=style.value("middleEnabled").toBool();p[14]=style.value("original").toBool()&&!mono;p[15]=0;
    const QColor flat=style.value("monoLight").toBool()?Qt::black:Qt::white;
    for(auto entry:{std::pair<int,const char *>{16,"bottom"},{20,"middle"},{24,"top"}}) {
        QColor c=mono?flat:style.value(entry.second,QColor("#e1e5f1")).value<QColor>();
        if(!c.isValid())c=QColor("#e1e5f1");
        p[entry.first]=c.redF();p[entry.first+1]=c.greenF();p[entry.first+2]=c.blueF();p[entry.first+3]=c.alphaF();
    }
    node->shader.levels=r.levels;
    for(int row=0;row<AmbientResponse::Rows;++row)for(int i=0;i<AmbientResponse::Columns;++i) {
        int offset=(row*AmbientResponse::Columns+i)*4;
        node->shader.history[offset]=r.history[row][i];node->shader.history[offset+1]=r.waveHistory[row][i];
    }
    node->markDirty(QSGNode::DirtyMaterial);node->cpuNs+=timer.nsecsElapsed();++node->frames;return node;
}
