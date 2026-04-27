/*
    SPDX-FileCopyrightText: 2026 Bake-Ware

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QList>
#include <QVector3D>

namespace KWin
{

/**
 * SnapRow — 1D row pack along X with a fixed gap between siblings.
 * Centers the row on the container origin. Each item's X is its
 * cumulative-width-so-far + half its own width − totalRowWidth/2.
 *
 * Used by snap containers.
 */
class SnapRowMode
{
public:
    static QVector3D positionAt(int idx, const QList<qreal> &widths, qreal gap);
};

} // namespace KWin
