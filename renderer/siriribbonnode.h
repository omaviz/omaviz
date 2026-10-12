#pragma once
#include <QSGNode>
#include <QVariantMap>
#include <QVariantList>

// Called only by the shared renderer on the scene-graph render thread.
QSGNode *updateSiriRibbonNode(QSGNode *old, const QVariantMap &style,
                       const QVariantList &bands, const QVariantList &wave, double phase,
                       float width, float height, float dpr);
