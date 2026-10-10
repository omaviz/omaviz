#pragma once
#include <QSGNode>
#include <QVariantMap>
#include <QVariantList>
QSGNode *updateSpectrumNode(QSGNode *,const QVariantMap &,const QVariantList &,
                            const QVariantList &,float,float,float);
