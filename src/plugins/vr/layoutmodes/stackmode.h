/*
    SPDX-FileCopyrightText: 2026 Bake-Ware

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include "ilayoutmode.h"

namespace KWin
{

/**
 * Stack mode: Z-only accumulator. Bidirectional walk from centerIndex,
 * forward and backward, summing per-pair max(flexibleDepth, hardDepth).
 *
 * Bit-identical to the layout math previously inlined in
 * ZStacker::recomputeLayout().
 */
class StackMode : public ILayoutMode
{
public:
    LayoutResult apply(const QList<LayoutItem> &items,
                       const ZMargins &initialMargins,
                       int centerIndex) override;
};

} // namespace KWin
