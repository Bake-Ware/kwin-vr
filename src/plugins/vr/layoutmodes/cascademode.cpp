/*
    SPDX-FileCopyrightText: 2026 Bake-Ware

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "cascademode.h"

namespace KWin
{

QVector3D CascadeMode::positionAt(int idx, qreal stepX, qreal stepY, qreal stepZ)
{
    return QVector3D(stepX * idx, stepY * idx, stepZ * idx);
}

} // namespace KWin
