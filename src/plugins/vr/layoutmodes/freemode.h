/*
    SPDX-FileCopyrightText: 2026 Bake-Ware

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QtGlobal>

namespace KWin
{

/**
 * Free — children placed at arbitrary positions on the container.
 * No auto-layout; layout is whatever the slot's position override says.
 *
 * Helper here covers only the optional "stackChildren" behavior:
 * when true, each child gets a compounding +Z lift so overlapping
 * children float forward of each other and the host plane.
 *
 * (Pseudomirrors use this; user-created Free containers do not.)
 */
class FreeMode
{
public:
    static qreal stackOffsetZ(int idx, qreal step);
};

} // namespace KWin
