#include "artworkpalette.h"
#include <QCoreApplication>
#include <QImage>
#include <QBuffer>
#include <QColor>
#include <QTemporaryFile>
#include <QEventLoop>
#include <QTimer>
#include <cstdlib>

void check(bool ok) { if(!ok) std::abort(); }
QByteArray encoded(const QImage &image) {
    QByteArray bytes; QBuffer buffer(&bytes); buffer.open(QIODevice::WriteOnly);
    check(image.save(&buffer,"PNG")); return bytes;
}
int main(int argc, char **argv) {
    QCoreApplication app(argc,argv);
    check(ArtworkPalette::extract("invalid image").isEmpty());
    QImage image(48,48,QImage::Format_ARGB32);
    const QColor colors[]={QColor("#008c95"),QColor("#663cc8"),QColor("#c5c94b")};
    for(int y=0;y<48;++y) for(int x=0;x<48;++x) image.setPixelColor(x,y,colors[x/16]);
    auto bytes=encoded(image);
    auto palette=ArtworkPalette::extract(bytes);
    check(palette.size()==3);
    for(auto expected:colors) {
        bool found=false;
        for(auto value:palette) {
            auto actual=value.value<QColor>();
            if(std::abs(actual.hsvHueF()-expected.hsvHueF())<.02) found=true;
        }
        check(found);
    }
    image.fill(Qt::transparent); check(ArtworkPalette::extract(encoded(image)).isEmpty());
    image.fill(QColor("#555555")); palette=ArtworkPalette::extract(encoded(image));
    check(palette.size()==3 && palette[0]==palette[1] && palette[1]==palette[2]);
    QTemporaryFile file; check(file.open()); file.write(bytes); file.flush();
    ArtworkPalette extractor;
    QEventLoop loop;
    QObject::connect(&extractor,&ArtworkPalette::colorsChanged,&loop,[&] { if(!extractor.colors().isEmpty()) loop.quit(); });
    QTimer::singleShot(2000,&loop,&QEventLoop::quit);
    extractor.setSource(QUrl::fromLocalFile(file.fileName())); loop.exec();
    check(extractor.colors().size()==3);
    extractor.setSource(QUrl()); check(extractor.colors().isEmpty());
    // Clearing a pending request must not allow a late reply to restore stale colors.
    extractor.setSource(QUrl::fromLocalFile(file.fileName())); extractor.setSource(QUrl());
    QTimer::singleShot(30,&loop,&QEventLoop::quit); loop.exec();
    check(extractor.colors().isEmpty());
}
