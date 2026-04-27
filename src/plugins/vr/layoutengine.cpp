/*
    SPDX-FileCopyrightText: 2026 Bake-Ware

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "layoutengine.h"

#include "layoutmodes/cascademode.h"
#include "layoutmodes/freemode.h"
#include "layoutmodes/snaprowmode.h"

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

} // namespace KWin
