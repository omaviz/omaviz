#pragma once
#include <QSGNode>
#include <QVariantMap>
#include <QVariantList>

QSGNode *updateStringsNode(QSGNode *old, const QVariantMap &style,
                          const QVariantList &bands, const QVariantList &wave,
                          double phase, float width, float height, float dpr);
