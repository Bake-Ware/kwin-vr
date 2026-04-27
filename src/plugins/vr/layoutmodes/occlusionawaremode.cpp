/*
    SPDX-FileCopyrightText: 2026 Bake-Ware

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "occlusionawaremode.h"

namespace KWin
{

static bool overlapsAny(const QRectF &candidate,
                        const QList<int> &classesSoFar,
                        const QList<OcclusionItem> &items,
                        int candidateClass,
                        int upToIndex)
{
    for (int j = 0; j < upToIndex; ++j) {
        if (classesSoFar[j] > candidateClass) {
            continue; // earlier item is on a higher class — can't occlude
        }
        if (classesSoFar[j] != candidateClass) {
            // earlier on lower class — only blocks if we're about to share its class
            // (We only care about same-class collisions for placement purposes.)
            // But sticky check uses lower-or-equal; let's filter to equal only
            // when assigning, lower-equal when sticky-validating.
            // Use equal for placement (an item only collides with same-class neighbours).
            continue;
        }
        if (candidate.intersects(items[j].footprint)) {
            return true;
        }
    }
    return false;
}

QList<int> OcclusionAwareMode::classify(const QList<OcclusionItem> &items)
{
    QList<int> classes;
    classes.reserve(items.size());

    for (int i = 0; i < items.size(); ++i) {
        const auto &item = items[i];
        int chosen = -1;

        // Sticky first: try previousZClass if valid.
        if (item.previousZClass >= 0) {
            classes.append(item.previousZClass);
            if (!overlapsAny(item.footprint, classes, items, item.previousZClass, i)) {
                continue; // sticky kept; classes already has correct value
            }
            classes.removeLast(); // doesn't fit; fall through to fresh search
        }

        // Walk classes 0,1,2,… find first non-overlapping.
        for (int k = 0;; ++k) {
            classes.append(k);
            if (!overlapsAny(item.footprint, classes, items, k, i)) {
                chosen = k;
                break;
            }
            classes.removeLast();
        }
        Q_UNUSED(chosen);
    }

    return classes;
}

} // namespace KWin
