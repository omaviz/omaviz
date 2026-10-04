#include <QQmlExtensionPlugin>
#include <qqml.h>
#include "geometry.h"
#include "artworkpalette.h"
class OmavizRendererPlugin final : public QQmlExtensionPlugin {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)
public:
    void registerTypes(const char *uri) override {
        qmlRegisterType<ArtworkPalette>(uri, 1, 0, "ArtworkPalette");
        qmlRegisterType<VisualGeometry>(uri, 1, 0, "VisualGeometry");
    }
};
#include "plugin.moc"
