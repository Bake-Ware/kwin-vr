/*
    SPDX-FileCopyrightText: 2026 Bake-Ware

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "snaprowmode.h"

namespace KWin
{

QVector3D SnapRowMode::positionAt(int idx, const QList<qreal> &widths, qreal gap)
{
    if (idx < 0 || idx >= widths.size()) {
        return QVector3D(0, 0, 0);
    }

    qreal totalW = 0;
    for (int i = 0; i < widths.size(); ++i) {
        totalW += widths[i];
        if (i > 0) {
            totalW += gap;
        }
    }

    qreal cumX = 0;
    for (int i = 0; i < idx; ++i) {
        cumX += widths[i] + gap;
    }

    const qreal myW = widths[idx];
    const qreal x = cumX + myW / 2 - totalW / 2;
    return QVector3D(static_cast<float>(x), 0, 0);
}

} // namespace KWin
