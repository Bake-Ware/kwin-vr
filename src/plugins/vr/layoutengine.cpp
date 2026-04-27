/*
    SPDX-FileCopyrightText: 2026 Bake-Ware

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "layoutengine.h"

#include "layoutmodes/cascademode.h"
#include "layoutmodes/freemode.h"
#include "layoutmodes/occlusionawaremode.h"
#include "layoutmodes/snaprowmode.h"

#include <QRectF>

namespace KWin
{

LayoutEngine::LayoutEngine(QObject *parent)
    : QObject(parent)
{
}

QVector3D LayoutEngine::cascadePosition(int idx, qreal stepX, qreal stepY, qreal stepZ) const
{
    return CascadeMode::positionAt(idx, stepX, stepY, stepZ);
}

QVector3D LayoutEngine::snapRowPosition(int idx, const QVariantList &widths, qreal gap) const
{
    QList<qreal> ws;
    ws.reserve(widths.size());
    for (const QVariant &v : widths) {
        ws.append(v.toReal());
    }
    return SnapRowMode::positionAt(idx, ws, gap);
}

qreal LayoutEngine::freeStackZ(int idx, qreal step) const
{
    return FreeMode::stackOffsetZ(idx, step);
}

QVariantList LayoutEngine::classifyOcclusion(const QVariantList &items) const
{
    QList<OcclusionItem> input;
    input.reserve(items.size());
    for (const QVariant &v : items) {
        QVariantMap m = v.toMap();
        OcclusionItem oi;
        oi.footprint = m.value(QStringLiteral("footprint")).toRectF();
        oi.previousZClass = m.value(QStringLiteral("previousZClass"), -1).toInt();
        input.append(oi);
    }

    QList<int> classes = OcclusionAwareMode::classify(input);

    QVariantList out;
    out.reserve(classes.size());
    for (int c : classes) {
        out.append(c);
    }
    return out;
}

} // namespace KWin
