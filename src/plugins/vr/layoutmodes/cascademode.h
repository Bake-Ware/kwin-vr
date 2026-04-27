/*
    SPDX-FileCopyrightText: 2026 Bake-Ware

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QVector3D>

namespace KWin
{

/**
 * Cascade — diagonal step per index. (stepX*i, stepY*i, stepZ*i).
 * Used by stack containers (windows piled with constant offset, last on top).
 *
 * Sign convention: +Z = forward (toward camera). For typical
 * cascade, stepY < 0 (down) so each layer reveals the bottom of the
 * one underneath.
 */
class CascadeMode
{
public:
    static QVector3D positionAt(int idx, qreal stepX, qreal stepY, qreal stepZ);
};

} // namespace KWin
