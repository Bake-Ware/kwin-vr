/*
    SPDX-FileCopyrightText: 2026 Bake-Ware

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "stackmode.h"

#include <algorithm>
#include <climits>

namespace KWin
{

LayoutResult StackMode::apply(const QList<LayoutItem> &items,
                              const ZMargins &initialMargins,
                              int centerIndex)
{
    LayoutResult result;

    QList<LayoutItem> sorted = items;
    std::sort(sorted.begin(), sorted.end(), [](const LayoutItem &a, const LayoutItem &b) {
        return a.index < b.index;
    });

    int closestIndexToCenter = INT_MIN;
    qreal targetZOffset = 0;
    auto prevZMargins = initialMargins;

    // Forward walk: centerIndex .. end
    for (int i = 0; i < sorted.size(); ++i) {
        const auto &item = sorted[i];
        if (item.index < centerIndex) {
            closestIndexToCenter = i;
            continue;
        }
        const auto &curr = item.itemDepth;
        const qreal flexibleDepth = prevZMargins.flexibleTop + curr.flexibleBottom;
        const qreal hardDepth = prevZMargins.top + curr.bottom;
        const qreal effectiveDepth = std::max(flexibleDepth, hardDepth);
        prevZMargins = curr;
        targetZOffset += effectiveDepth;
        result.placements[item.obj] = LayoutOutput{0, 0, targetZOffset, 0};
    }

    result.totalDepth.top = targetZOffset + prevZMargins.top;

    // Backward walk: closestIndexToCenter .. 0
    targetZOffset = 0;
    prevZMargins = initialMargins;
    for (int i = closestIndexToCenter; i >= 0; --i) {
        const auto &item = sorted[i];
        const auto &curr = item.itemDepth;
        const qreal flexibleDepth = prevZMargins.flexibleBottom + curr.flexibleTop;
        const qreal hardDepth = prevZMargins.bottom + curr.top;
        const qreal effectiveDepth = std::max(flexibleDepth, hardDepth);
        prevZMargins = curr;
        targetZOffset -= effectiveDepth;
        result.placements[item.obj] = LayoutOutput{0, 0, targetZOffset, 0};
    }

    result.totalDepth.bottom = -targetZOffset + prevZMargins.bottom;

    return result;
}

} // namespace KWin
