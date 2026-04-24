/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick3D

/*
 * WorkSurfaceRegistry — scene-level manager for WorkSurface instances.
 * Lives as a child of XrScene (hosted under allWindowsGrabHandle so
 * surfaces inherit the world-grab transform).
 *
 * Phase 1 scaffolding — data + lookup only. join/detach/bisect logic
 * lands in follow-up commits.
 */
Node {
    id: root

    /* Active surfaces. Keyed by surfaceId → WorkSurface instance. */
    property var surfaces: ({})

    property int _nextId: 1

    function surfaceForWindow(w) {
        return w ? w.workSurface : null
    }

    function _newId() {
        return "ws_" + (_nextId++)
    }
}
