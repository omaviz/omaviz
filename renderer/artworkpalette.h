#pragma once
#include <QObject>
#include <QUrl>
#include <QVariantList>
#include <QNetworkAccessManager>
#include <QPointer>
#include <QNetworkReply>

// Extract only when artwork changes, never in the animation/render loop.
class ArtworkPalette : public QObject {
    Q_OBJECT
    Q_PROPERTY(QUrl source READ source WRITE setSource NOTIFY sourceChanged)
    Q_PROPERTY(QVariantList colors READ colors NOTIFY colorsChanged)
public:
    explicit ArtworkPalette(QObject *parent=nullptr): QObject(parent), network(this) {}
    QUrl source() const { return url; }
    QVariantList colors() const { return tones; }
    void setSource(const QUrl &value);
    static QVariantList extract(const QByteArray &bytes);
signals:
    void sourceChanged();
    void colorsChanged();
private:
    QUrl url;
    QVariantList tones;
    QNetworkAccessManager network;
    QPointer<QNetworkReply> pending;
};
