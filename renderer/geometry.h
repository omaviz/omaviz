#pragma once
#include <QQuickItem>
#include <QVariantMap>
#include <QVariantList>

// One scene-graph implementation for every host surface. GUI-thread setters
// copy snapshots; updatePaintNode consumes them while Qt blocks the GUI thread.
class VisualGeometry : public QQuickItem {
    Q_OBJECT
    Q_PROPERTY(QVariantMap style READ style WRITE setStyle NOTIFY styleChanged)
public:
    explicit VisualGeometry(QQuickItem *parent = nullptr);
    QVariantMap style() const { return m_style; }
    void setStyle(const QVariantMap &value);
    Q_INVOKABLE void submit(const QVariantList &bars, const QVariantList &peaks,
                            const QVariantList &wave, double phase);
signals:
    void styleChanged();
protected:
    QSGNode *updatePaintNode(QSGNode *, UpdatePaintNodeData *) override;
    void geometryChange(const QRectF &, const QRectF &) override;
private:
    QVariantMap m_style;
    QVariantList m_bars, m_peaks, m_wave;
    double m_phase = 0;
};
