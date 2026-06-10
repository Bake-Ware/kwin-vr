/*
    SPDX-FileCopyrightText: 2026 Bake-Ware

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

// Registry of WindowGroup instances — register/unregister + lookup.
// Data-only scaffold salvaged from acba70807b (#25); no persistence yet.
//
// Deviation from the archived design: scene-owned instance, not a
// pragma Singleton — a singleton would carry group state across VR
// session restarts, and an instantiable object is directly qmltest-able.
// The owning scene instantiates exactly one.
QtObject {
    id: root

    // Array of WindowGroup refs. Replaced wholesale on change so bindings fire.
    property var groups: []

    signal groupRegistered(var group)
    signal groupUnregistered(string groupId)

    function _newId() {
        return "wg_" + Date.now().toString(36) + "_" + Math.floor(Math.random() * 1e6).toString(36)
    }

    function registerGroup(group) {
        if (!group) return null
        if (!group.groupId || group.groupId === "")
            group.groupId = _newId()
        if (findById(group.groupId)) return group
        const next = groups.slice()
        next.push(group)
        groups = next
        groupRegistered(group)
        return group
    }

    function unregisterGroup(groupId) {
        const idx = _indexOf(groupId)
        if (idx === -1) return
        const next = groups.slice()
        next.splice(idx, 1)
        groups = next
        groupUnregistered(groupId)
    }

    function findById(groupId) {
        const idx = _indexOf(groupId)
        return idx === -1 ? null : groups[idx]
    }

    function findContaining(node) {
        for (let i = 0; i < groups.length; ++i) {
            if (groups[i] && groups[i].hasMember(node))
                return groups[i]
        }
        return null
    }

    function _indexOf(groupId) {
        for (let i = 0; i < groups.length; ++i) {
            if (groups[i] && groups[i].groupId === groupId) return i
        }
        return -1
    }
}
