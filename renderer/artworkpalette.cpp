#include "artworkpalette.h"
#include <QBuffer>
#include <QImageReader>
#include <QColor>
#include <QNetworkRequest>
#include <QTimer>
#include <QtEndian>
#include <array>
#include <algorithm>

namespace {
constexpr qsizetype MaxDownload=12*1024*1024;
constexpr quint64 MaxPixels=4*1024*1024;
QByteArray pixelPng(const QByteArray &input) {
    // Qt's allocation limit covers pixels, not libpng's decompressed text/ICC
    // chunks. Never pass those chunks to a decoder, even after the IDAT data.
    static const QByteArray signature("\x89PNG\r\n\x1a\n",8);
    if(!input.startsWith(signature)) return {};
    QByteArray output=signature;
    bool header=false,data=false;
    qsizetype offset=8;
    for(int chunks=0;chunks<4096 && offset+12<=input.size();++chunks) {
        const quint32 length=qFromBigEndian<quint32>(input.constData()+offset);
        if(quint64(length)+12>quint64(input.size()-offset)) return {};
        const QByteArray type=input.mid(offset+4,4);
        if(!header) {
            if(type!="IHDR" || length!=13) return {};
            const auto w=qFromBigEndian<quint32>(input.constData()+offset+8);
            const auto h=qFromBigEndian<quint32>(input.constData()+offset+12);
            if(!w || !h || w>8192 || h>8192 || quint64(w)*h>MaxPixels) return {};
            header=true;
        } else if(type=="IHDR") return {};
        const bool keep=type=="IHDR" || type=="PLTE" || type=="IDAT" || type=="IEND" || type=="tRNS";
        if((type=="PLTE" && length>768) || (type=="tRNS" && length>256)) return {};
        if(!keep && !(type[0]&0x20)) return {}; // Unknown critical chunk.
        if(type=="IDAT") data=true;
        if(keep) output.append(input.constData()+offset,qsizetype(length)+12);
        offset+=qsizetype(length)+12;
        if(type=="IEND") return length==0 && data && offset==input.size()?output:QByteArray();
    }
    return {};
}
QVariantList colorsFromImage(const QImage &source) {
    const auto image=source.scaled(48,48,Qt::IgnoreAspectRatio,Qt::SmoothTransformation);
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
        c=QColor::fromHsvF(c.hsvHueF(),c.saturationF(),std::max(.45f,c.valueF()));
        result.append(c);
    }
    if(result.isEmpty()) return {};
    while(result.size()<3) result.append(result.last());
    return result;
}
}

QImage ArtworkPalette::decode(const QByteArray &bytes) {
    if(bytes.isEmpty() || bytes.size()>MaxDownload) return {};
    QByteArray safe,format;
    if(bytes.startsWith(QByteArray("\x89PNG\r\n\x1a\n",8))) { safe=pixelPng(bytes);format="png"; }
    else if(bytes.startsWith(QByteArray("\xff\xd8\xff",3))) { safe=bytes;format="jpeg"; }
    else if(bytes.size()>=12 && bytes.startsWith("RIFF") && bytes.mid(8,4)=="WEBP") { safe=bytes;format="webp"; }
    else return {}; // No vector documents or arbitrary image plugins.
    if(safe.isEmpty()) return {};
    QBuffer buffer;
    buffer.setData(safe);
    buffer.open(QIODevice::ReadOnly);
    QImageReader reader(&buffer,format);
    reader.setAutoDetectImageFormat(false);
    reader.setDecideFormatFromContent(false);
    const auto size=reader.size();
    if(size.isEmpty() || size.width()>8192 || size.height()>8192 || quint64(size.width())*size.height()>MaxPixels) return {};
    reader.setAutoTransform(true);
    reader.setScaledSize(size.width()>192 || size.height()>192?size.scaled(192,192,Qt::KeepAspectRatio):size);
    const auto decoded=reader.read();
    if(decoded.isNull()) return {};
    // Copy pixels only: no text, profiles, or orientation metadata propagates
    // into the trusted thumbnail subsequently decoded by QML Image.
    const auto small=decoded.width()>192 || decoded.height()>192?decoded.scaled(192,192,Qt::KeepAspectRatio,Qt::SmoothTransformation):decoded;
    QImage pixels(small.size(),QImage::Format_ARGB32);
    for(int y=0;y<small.height();++y) for(int x=0;x<small.width();++x) pixels.setPixelColor(x,y,small.pixelColor(x,y));
    return pixels;
}

QVariantList ArtworkPalette::extract(const QByteArray &bytes) { return colorsFromImage(decode(bytes)); }

void ArtworkPalette::setSource(const QUrl &value) {
    if(url==value) return;
    url=value;
    if(pending) { auto old=pending; pending=nullptr; old->abort(); }
    tones.clear(); thumbnail=QUrl(); emit sourceChanged(); emit colorsChanged();
    if(url.isEmpty() || (url.scheme()!="file" && url.scheme()!="https" && url.scheme()!="http")) return;
    QNetworkRequest request(url);
    request.setTransferTimeout(10000);
    auto reply=network.get(request);
    reply->setReadBufferSize(MaxDownload+1);
    QTimer::singleShot(10000,reply,[reply] { if(!reply->isFinished()) reply->abort(); });
    pending=reply;
    connect(reply,&QNetworkReply::readyRead,this,[reply] {
        if(reply->bytesAvailable()>MaxDownload) reply->abort();
    });
    connect(reply,&QNetworkReply::finished,this,[this,reply] {
        if(pending==reply) {
            pending=nullptr;
            if(reply->error()==QNetworkReply::NoError) {
                const auto image=decode(reply->readAll());
                tones=colorsFromImage(image);
                if(!image.isNull()) {
                    QByteArray png;QBuffer output(&png);output.open(QIODevice::WriteOnly);
                    if(image.save(&output,"PNG")) thumbnail=QUrl(QStringLiteral("data:image/png;base64,")+QString::fromLatin1(png.toBase64()));
                }
            }
            emit colorsChanged();
        }
        reply->deleteLater();
    });
}
