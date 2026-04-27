/*
    SPDX-FileCopyrightText: 2026 Bake-Ware

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "freemode.h"

namespace KWin
{

qreal FreeMode::stackOffsetZ(int idx, qreal step)
{
    return (idx + 1) * step;
}

} // namespace KWin
