/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

/*
 * VrBarrierConstraint - Creates a barrier at screen edges and
 * emits beyondMargin() when pointer breaks through the barrier.
 */
VrPointerConstraint {
    id: root

    // Screen bounds to constrain within
    property rect bounds

    // Distance beyond screen edge before pointer breaks through the barrier
    property int margin: 50

    // Emitted when pointer breaks through the barrier
    signal beyondMargin()

    function filter(pos: point): point {
        if (!root.enabled)
            return pos

        const dominated =
            pos.x < (bounds.left - margin) ||
            pos.x > (bounds.right + margin) ||
            pos.y < (bounds.top - margin) ||
            pos.y > (bounds.bottom + margin)

        if (dominated) {
            root.beyondMargin()
        }

        // Clamp to screen bounds (barrier effect)
        return Qt.point(
            Math.max(bounds.left, Math.min(bounds.right - 1, pos.x)),
            Math.max(bounds.top, Math.min(bounds.bottom - 1, pos.y))
        )
    }
}
