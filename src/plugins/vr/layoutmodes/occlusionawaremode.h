/*
    SPDX-FileCopyrightText: 2026 Bake-Ware

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QList>
#include <QRectF>

namespace KWin
{

/**
 * Occlusion-aware Z classification.
 *
 * Sticky first-fit: each item carries a (footprint, previousZClass).
 * In iteration order, try the item's previous class first; if it
 * doesn't overlap any earlier-assigned item at the same-or-lower
 * class, keep it. Else walk classes 0, 1, 2, … and assign the first
 * non-overlapping class.
 *
 * For N ≤ ~20 (typical windows-on-a-plane count), brute-force pairwise
 * AABB compare is faster than any spatial index.
 */
struct OcclusionItem
{
    QRectF footprint; // xy bounds in container space
    int previousZClass = -1; // -1 → no prior assignment
};

class OcclusionAwareMode
{
public:
    /**
     * Returns a list of assigned z-classes parallel to the input list.
     * out[i] = z-class for items[i]. Class 0 = nearest the plane.
     */
    static QList<int> classify(const QList<OcclusionItem> &items);
};

} // namespace KWin
