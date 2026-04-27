/*
    SPDX-FileCopyrightText: 2026 Bake-Ware

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include "../zmargins.h"

#include <QHash>
#include <QList>
#include <QSizeF>

class QQuick3DObject;

namespace KWin
{

struct LayoutItem
{
    QQuick3DObject *obj = nullptr;
    int index = -1;
    int layer = 0;
    ZMargins itemDepth;
    QSizeF footprint;
    int previousZClass = -1;
};

struct LayoutOutput
{
    qreal xOffset = 0;
    qreal yOffset = 0;
    qreal zOffset = 0;
    int zClass = 0;
};

struct LayoutResult
{
    QHash<QQuick3DObject *, LayoutOutput> placements;
    ZMargins totalDepth;
};

class ILayoutMode
{
public:
    virtual ~ILayoutMode() = default;
    virtual LayoutResult apply(const QList<LayoutItem> &items,
                               const ZMargins &initialMargins,
                               int centerIndex) = 0;
};

} // namespace KWin
