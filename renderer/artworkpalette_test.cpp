#include "artworkpalette.h"
#include <QCoreApplication>
#include <QImage>
#include <QBuffer>
#include <QColor>
#include <QTemporaryFile>
#include <QEventLoop>
#include <QTimer>
#include <QProcess>
#include <QImageReader>
#include <QtEndian>
#ifdef Q_OS_UNIX
#include <sys/resource.h>
#endif
#include <cstdlib>

void check(bool ok) { if(!ok) std::abort(); }
QByteArray encoded(const QImage &image) {
    QByteArray bytes; QBuffer buffer(&bytes); buffer.open(QIODevice::WriteOnly);
    check(image.save(&buffer,"PNG")); return bytes;
}
QByteArray chunk(const QByteArray &type,const QByteArray &payload) {
    QByteArray body=type+payload,result(4,0);
    qToBigEndian<quint32>(quint32(payload.size()),result.data());
    quint32 crc=0xffffffff;
    for(unsigned char byte:body) { crc^=byte;for(int i=0;i<8;++i)crc=(crc>>1)^((crc&1)?0xedb88320:0); }
    result+=body;QByteArray checksum(4,0);qToBigEndian<quint32>(crc^0xffffffff,checksum.data());return result+checksum;
}
QByteArray metadataBomb() {
    QImage image(48,48,QImage::Format_ARGB32);image.fill(QColor("#008c95"));
    const auto base=encoded(image);
    const auto compressed=qCompress(QByteArray(1024*1024,'a')).mid(4);
    QByteArray ancillary;
    // 512 individually small compressed chunks would expand to 512 MiB.
    for(int i=0;i<512;++i) ancillary+=chunk("zTXt",QByteArray("note\0\0",6)+compressed);
    ancillary+=chunk("iTXt",QByteArray("note\0\1\0\0\0",9)+compressed);
    ancillary+=chunk("iCCP",QByteArray("profile\0\0",9)+compressed);
    return base.left(33)+ancillary+base.mid(33,base.size()-45)+ancillary+base.right(12);
}
int main(int argc, char **argv) {
    QCoreApplication app(argc,argv);
    if(argc>1 && QByteArray(argv[1])=="--metadata-bomb") {
#ifdef Q_OS_UNIX
        rlimit limit{256*1024*1024,256*1024*1024};check(setrlimit(RLIMIT_AS,&limit)==0);
#endif
        const auto bomb=metadataBomb();check(bomb.size()<12*1024*1024);
        check(ArtworkPalette::extract(bomb).size()==3);
        const auto safe=ArtworkPalette::decode(bomb);check(!safe.isNull() && safe.textKeys().isEmpty());
        return 0;
    }
    QProcess attack;attack.start(QCoreApplication::applicationFilePath(),{"--metadata-bomb"});
    check(attack.waitForFinished(5000));check(attack.exitStatus()==QProcess::NormalExit && attack.exitCode()==0);
    const auto allocation=QImageReader::allocationLimit();
    check(ArtworkPalette::extract("invalid image").isEmpty());
    check(ArtworkPalette::decode(QByteArray(12*1024*1024+1,'x')).isNull());
    check(ArtworkPalette::decode("<svg xmlns='http://www.w3.org/2000/svg' width='100' height='100'/>").isNull());
    QImage image(48,48,QImage::Format_ARGB32);
    const QColor colors[]={QColor("#008c95"),QColor("#663cc8"),QColor("#c5c94b")};
    for(int y=0;y<48;++y) for(int x=0;x<48;++x) image.setPixelColor(x,y,colors[x/16]);
    auto bytes=encoded(image);
    QByteArray jpeg;QBuffer jpegBuffer(&jpeg);jpegBuffer.open(QIODevice::WriteOnly);
    image.setText("Comment","metadata is not forwarded");check(image.save(&jpegBuffer,"JPEG"));
    const auto jpegPixels=ArtworkPalette::decode(jpeg);check(!jpegPixels.isNull() && jpegPixels.textKeys().isEmpty());
    auto truncated=bytes;truncated.truncate(40);check(ArtworkPalette::decode(truncated).isNull());
    auto enormous=bytes;qToBigEndian<quint32>(100000,enormous.data()+16);check(ArtworkPalette::decode(enormous).isNull());
    check(ArtworkPalette::decode(bytes.left(8)+chunk("IHDR",QByteArray(13,0))).isNull());
    check(ArtworkPalette::decode(bytes.left(33)+chunk("ABCD","critical")+bytes.mid(33)).isNull());
    check(ArtworkPalette::decode(bytes.left(33)+chunk("tEXt",QByteArray("note\0hello",10))+bytes.mid(33)).textKeys().isEmpty());
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
    check(extractor.imageSource().toString().startsWith("data:image/png;base64,"));
    check(!QImage::fromData(QByteArray::fromBase64(extractor.imageSource().toString().section(',',1).toLatin1()),"PNG").isNull());
    extractor.setSource(QUrl()); check(extractor.colors().isEmpty() && extractor.imageSource().isEmpty());
    // Clearing a pending request must not allow a late reply to restore stale colors.
    extractor.setSource(QUrl::fromLocalFile(file.fileName())); extractor.setSource(QUrl());
    QTimer::singleShot(30,&loop,&QEventLoop::quit); loop.exec();
    check(extractor.colors().isEmpty());
    check(extractor.imageSource().isEmpty());
    check(QImageReader::allocationLimit()==allocation); // Never mutate the host shell's global decoder settings.
}
