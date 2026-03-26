/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

/*
 * VrPointerConstraint - Base class for pointer position filters/constraints.
 *
 * Subclasses override filter() to implement specific constraint logic.
 */
QtObject {
    id: root

    // Whether this constraint is active
    property bool enabled: true

    // Override in subclasses. Returns filtered position, or input unchanged.
    function filter(pos: point): point {
        return pos  // passthrough by default
    }
}
