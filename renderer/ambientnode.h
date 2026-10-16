#pragma once
#include <QSGNode>
#include <QVariantList>
#include <QVariantMap>

QSGNode *updateAmbientNode(QSGNode *old,const QVariantMap &style,const QVariantList &bands,
                           const QVariantList &wave,double phase,float width,float height,float dpr);
