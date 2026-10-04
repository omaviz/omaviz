#include "artworkpalette.h"
#include <QBuffer>
#include <QImageReader>
#include <QColor>
#include <QNetworkRequest>
#include <array>
#include <algorithm>

QVariantList ArtworkPalette::extract(const QByteArray &bytes) {
    QBuffer buffer;
    buffer.setData(bytes);
    buffer.open(QIODevice::ReadOnly);
    QImageReader reader(&buffer);
    reader.setAutoTransform(true);
    reader.setScaledSize(QSize(48,48));
    const auto image=reader.read().scaled(48,48,Qt::IgnoreAspectRatio,Qt::SmoothTransformation);
    if(image.isNull()) return {};
    struct Bin { double r=0,g=0,b=0,weight=0; };
    std::array<Bin,13> bins{};
    for(int y=0;y<image.height();++y) for(int x=0;x<image.width();++x) {
        QColor c=image.pixelColor(x,y);
        if(c.alphaF()<.5 || c.valueF()<.08 || (c.valueF()>.96 && c.saturationF()<.12)) continue;
        int index=c.saturationF()<.15?12:std::min(11,int(c.hsvHueF()*12));
        double weight=.2+c.saturationF();
        auto &bin=bins[index];
        bin.r+=c.redF()*weight; bin.g+=c.greenF()*weight; bin.b+=c.blueF()*weight; bin.weight+=weight;
    }
    std::sort(bins.begin(),bins.end(),[](const Bin &a,const Bin &b){return a.weight>b.weight;});
    QVariantList result;
    for(const auto &bin:bins) {
        if(bin.weight<=0 || result.size()==3) break;
        QColor c=QColor::fromRgbF(bin.r/bin.weight,bin.g/bin.weight,bin.b/bin.weight);
        // Preserve cover hues while lifting very dark artwork for readable bars.
        c=QColor::fromHsvF(c.hsvHueF(),c.saturationF(),std::max(.45f,c.valueF()));
        result.append(c);
    }
    if(result.isEmpty()) return {};
    while(result.size()<3) result.append(result.last());
    return result;
}

void ArtworkPalette::setSource(const QUrl &value) {
    if(url==value) return;
    url=value;
    if(pending) { auto old=pending; pending=nullptr; old->abort(); }
    tones.clear(); emit sourceChanged(); emit colorsChanged();
    if(url.isEmpty() || (url.scheme()!="file" && url.scheme()!="https" && url.scheme()!="http")) return;
    QNetworkRequest request(url);
    request.setTransferTimeout(10000);
    auto reply=network.get(request);
    pending=reply;
    connect(reply,&QNetworkReply::readyRead,this,[reply] {
        if(reply->bytesAvailable()>12*1024*1024) reply->abort();
    });
    connect(reply,&QNetworkReply::finished,this,[this,reply] {
        if(pending==reply) {
            pending=nullptr;
            if(reply->error()==QNetworkReply::NoError) tones=extract(reply->readAll());
            emit colorsChanged();
        }
        reply->deleteLater();
    });
}
