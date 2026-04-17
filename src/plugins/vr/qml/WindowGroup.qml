/*
    SPDX-FileCopyrightText: 2026 Bake-Ware

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick3D

// Lateral set of windows. No parent-child window relation.
// Members are siblings; each window orients independently.
// Anchor = centroid of members. Thumbtack (future) = group's grab handle.
Node {
    id: root

    enum Mode { Pinned, Stacked, Camera }

    property string groupId: ""
    property string label: ""
    property int mode: WindowGroup.Mode.Pinned

    // Members: array of Node refs (KwinApplicationWindow / mirror / etc).
    // Lateral — windows do not become children of this Node.
    property var members: []

    // Read-only anchor in scene space (centroid of member scenePositions).
    // Recomputed on demand; no per-frame binding (data-only scaffold).
    function recomputeAnchor() {
        if (!members || members.length === 0)
            return
        let sx = 0, sy = 0, sz = 0, n = 0
        for (let i = 0; i < members.length; ++i) {
            const m = members[i]
            if (!m || !m.scenePosition) continue
            sx += m.scenePosition.x
            sy += m.scenePosition.y
            sz += m.scenePosition.z
            n += 1
        }
        if (n === 0) return
        position = Qt.vector3d(sx / n, sy / n, sz / n)
    }

    function addMember(node) {
        if (!node) return
        if (members.indexOf(node) !== -1) return
        const next = members.slice()
        next.push(node)
        members = next
    }

    function removeMember(node) {
        const idx = members.indexOf(node)
        if (idx === -1) return
        const next = members.slice()
        next.splice(idx, 1)
        members = next
    }

    function hasMember(node) {
        return members.indexOf(node) !== -1
    }
}
