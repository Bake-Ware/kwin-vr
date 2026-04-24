/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick3D

/*
 * WorkSurface — ephemeral group container for snapped/stacked windows.
 * Holds group-level state (curvature, membership, adjacency) and acts
 * as the rigid transform anchor when the cluster is dragged.
 *
 * Lifecycle managed by WorkSurfaceRegistry. Do not instantiate directly
 * outside the registry.
 */
Node {
    id: root

    property string surfaceId: ""
    property real curvature: 0.0
    property var members: []
    property var adjacency: ({})
}
