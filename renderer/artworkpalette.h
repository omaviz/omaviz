#pragma once
#include <QObject>
#include <QUrl>
#include <QVariantList>
#include <QNetworkAccessManager>
#include <QPointer>
#include <QNetworkReply>
#include <QImage>

// Extract only when artwork changes, never in the animation/render loop.
class ArtworkPalette : public QObject {
    Q_OBJECT
    Q_PROPERTY(QUrl source READ source WRITE setSource NOTIFY sourceChanged)
    Q_PROPERTY(QVariantList colors READ colors NOTIFY colorsChanged)
    Q_PROPERTY(QUrl imageSource READ imageSource NOTIFY colorsChanged)
public:
    explicit ArtworkPalette(QObject *parent=nullptr): QObject(parent), network(this) {}
    QUrl source() const { return url; }
    QVariantList colors() const { return tones; }
    QUrl imageSource() const { return thumbnail; }
    void setSource(const QUrl &value);
    static QVariantList extract(const QByteArray &bytes);
    static QImage decode(const QByteArray &bytes);
signals:
    void sourceChanged();
    void colorsChanged();
private:
    QUrl url;
    QVariantList tones;
    QUrl thumbnail;
    QNetworkAccessManager network;
    QPointer<QNetworkReply> pending;
};
