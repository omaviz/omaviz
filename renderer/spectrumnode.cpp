#include "spectrumnode.h"
#include <QSGGeometryNode>
#include <QSGMaterial>
#include <QSGMaterialShader>
#include <QColor>
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
    return QColor::fromRgbF(a.redF()+(b.redF()-a.redF())*t,a.greenF()+(b.greenF()-a.greenF())*t,
                           a.blueF()+(b.blueF()-a.blueF())*t,a.alphaF()+(b.alphaF()-a.alphaF())*t);
}
struct Vertex { float x,y,index,kind,edge,section,row; };
const QSGGeometry::AttributeSet &attributes() {
    static const QSGGeometry::Attribute attrs[]={
        QSGGeometry::Attribute::create(0,2,QSGGeometry::FloatType,true),
        QSGGeometry::Attribute::create(1,4,QSGGeometry::FloatType),
        QSGGeometry::Attribute::create(2,1,QSGGeometry::FloatType)};
    static const QSGGeometry::AttributeSet set={3,sizeof(Vertex),attrs};return set;
}
class Shader:public QSGMaterialShader {
public:
    Shader() {
        setShaderFileName(VertexStage,QStringLiteral(":/omaviz/shaders/spectrum.vert.qsb"));
        setShaderFileName(FragmentStage,QStringLiteral(":/omaviz/shaders/siri.frag.qsb"));
    }
    bool updateUniformData(RenderState &,QSGMaterial *,QSGMaterial *) override;
};
class Material:public QSGMaterial {
public:
    std::array<float,32> params{};
    std::array<float,2048> bands{}; // two height/peak pairs per std140 vec4
    Material() {setFlag(Blending);setFlag(RequiresFullMatrix);setFlag(NoBatching);}
    QSGMaterialType *type() const override {static QSGMaterialType t;return &t;}
    QSGMaterialShader *createShader(QSGRendererInterface::RenderMode) const override {return new Shader;}
};
bool Shader::updateUniformData(RenderState &s,QSGMaterial *material,QSGMaterial *) {
    auto *data=s.uniformData();Q_ASSERT(data->size()>=8384);
    if(s.isMatrixDirty()) {auto matrix=s.combinedMatrix();std::memcpy(data->data(),matrix.constData(),64);}
    auto *m=static_cast<Material *>(material);m->params[0]=s.opacity();
    std::memcpy(data->data()+64,m->params.data(),128);
    std::memcpy(data->data()+192,m->bands.data(),8192);return true;
}
struct Node:QSGGeometryNode {
    QSGGeometry mesh{attributes(),0};Material shader;QVariantMap style;
    float width=0,height=0,dpr=0;int count=0;
    Node() {mesh.setDrawingMode(QSGGeometry::DrawTriangles);mesh.setVertexDataPattern(QSGGeometry::StaticPattern);
        setGeometry(&mesh);setMaterial(&shader);}
    void rebuild(const QVariantMap &s,int n,float w,float h,float scale) {
        style=s;count=n;width=w;height=h;dpr=scale;
        auto flag=[&](const char *k){return s.value(k).toBool();};
        auto number=[&](const char *k,float d){return finite(s.value(k,d).toFloat(),d);};
        auto color=[&](const char *k,const char *d){auto c=s.value(k,QColor(d)).value<QColor>();return c.isValid()?c:QColor(d);};
        bool mono=flag("mono"),fire=flag("fire"),horizontal=flag("horizontal"),spikes=flag("spikes"),stacks=flag("stacks");
        float pixel=1/std::max(1.f,scale),area=h*(flag("reflect")?.62f:1.f),base=h*(flag("reflect")?.68f:1.f);
        float gap=spikes?0:std::max(0.f,number("gap",1));
        float bw=spikes?w/std::max(n,1):std::max(pixel,(w-gap*std::max(n-1,0))/std::max(n,1))+number("extraWidth",0);
        float stackScale=std::max(1.f,number("stackScale",1));
        QColor flat=flag("monoLight")?Qt::black:Qt::white;
        QColor bottom=mono?flat:fire?color("fireBottom","#be1400"):color("bottom","#e68e0d");
        QColor top=mono?flat:fire?color("fireTop","#fde047"):color("top","#f59e0b");
        QColor middle=fire?mix(bottom,QColor(255,130,10),.25f/.3f):color("middle","#a855f7");
        bool split=!mono&&(fire||flag("middleEnabled"));float stop=fire?.25f:.5f;
        auto &p=shader.params;p={1,w,h,pixel,area,base,stackScale,stop,
            float(horizontal),float(split),float(stacks),spikes?std::min(bw*.8f,6.f):-1.f};
        auto put=[&](int offset,QColor c,bool packed){
            if(packed) {auto rgb=qPremultiply(c.rgba());p[offset]=qRed(rgb)/255.f;p[offset+1]=qGreen(rgb)/255.f;
                p[offset+2]=qBlue(rgb)/255.f;p[offset+3]=qAlpha(rgb)/255.f;}
            else {p[offset]=c.redF();p[offset+1]=c.greenF();p[offset+2]=c.blueF();p[offset+3]=c.alphaF();}
        };
        put(12,bottom,false);put(16,middle,false);put(20,top,false);
        put(24,mono?flat:spikes?QColor("#ffe9a8"):QColor(Qt::white),true);
        QColor reflection=fire&&split?mix(bottom,middle,.12f/stop):bottom;
        reflection.setAlphaF(unit(reflection.alphaF()*.22f));put(28,reflection,true);
        std::vector<Vertex> vertices;
        auto quad=[&](float l,float r,int i,int kind,int section,float row){
            for(auto corner:{0,1,2,0,2,3}) {
                float edge=corner>=2?1.f:0.f;
                vertices.push_back({corner==1||corner==2?r:l,edge*h,float(i),float(kind),edge,float(section),row});
            }
        };
        auto rect=[&](float l,float r,int i,int kind,float row){
            l=std::clamp(l,0.f,w);r=std::clamp(r,0.f,w);if(r<=l)return;
            if(horizontal&&!fire&&!mono&&flag("middleEnabled")&&l<w*.5f&&r>w*.5f){
                quad(l,w*.5f,i,kind,0,row);l=w*.5f;
            }
            quad(l,r,i,kind,0,row);
            if(!horizontal&&split)quad(l,r,i,kind,1,row);
        };
        if(flag("wash"))for(int i=0;i<n;++i)rect(i*w/n,(i+1)*w/n,i,1,0);
        for(int i=0;i<n;++i) {
            float x=std::round(i*(bw+gap)*scale)/scale,r=std::round((i*(bw+gap)+bw)*scale)/scale;
            if(stacks) {
                // Retain every possible tile; tiles above the current bar collapse.
                for(float sy=base;sy>base-std::max(pixel,area);sy-=4*stackScale)rect(x,r,i,0,sy);
            } else {
                rect(x,r,i,0,base);
                if(spikes) {
                    vertices.push_back({x,h,float(i),4,1,0,0});
                    vertices.push_back({r,h,float(i),4,1,0,0});
                    vertices.push_back({(x+r)/2,0,float(i),4,0,0,0});
                }
            }
            if(flag("peaks"))quad(x,r,i,2,0,0);
            if(flag("reflect"))quad(x,r,i,3,0,0);
        }
        mesh.allocate(int(vertices.size()));
        std::memcpy(mesh.vertexData(),vertices.data(),vertices.size()*sizeof(Vertex));
        mesh.markVertexDataDirty();markDirty(DirtyGeometry);
    }
};
}
QSGNode *updateSpectrumNode(QSGNode *old,const QVariantMap &style,const QVariantList &bars,
                            const QVariantList &peaks,float w,float h,float dpr) {
    if(w<=0||h<=0||bars.empty()){delete old;return nullptr;}
    auto *node=static_cast<Node *>(old);
    if(!node) {
        node=new Node;
        if(qEnvironmentVariableIsSet("OMAVIZ_PROFILE"))
            fprintf(stderr,"spectrum retained renderer active\n");
    }
    if(node->style!=style||node->width!=w||node->height!=h||node->dpr!=dpr||node->count!=bars.size())
        node->rebuild(style,int(bars.size()),w,h,dpr);
    for(int i=0;i<bars.size();++i) {
        node->shader.bands[i*2]=unit(bars[i].toFloat());
        node->shader.bands[i*2+1]=i<peaks.size()?unit(peaks[i].toFloat()):0;
    }
    node->markDirty(QSGNode::DirtyMaterial);return node;
}
