/*
    SPDX-FileCopyrightText: 2026 Bake-Ware

    SPDX-License-Identifier: GPL-2.0-or-later
*/

/*
 * PlaneRegistry — scene-level registry for every CurvedPlane in the scene.
 *
 * Holds:
 *   - planeId → Node map
 *   - a monotonically-increasing slotsRevision used as the dependency
 *     anchor for findAbductor() bindings. Bumped any time *anyone's*
 *     slots list changes, so descendants re-evaluate their abductor.
 *
 * Single instance lives in XrScene; reachable via xrView.planeRegistry.
 */

import QtQuick

QtObject {
    id: root

    property var _planes: ({})
    property int _nextId: 1

    // Bumped on any slot mutation. findAbductor reads this to anchor
    // its dependency tracking.
    property int slotsRevision: 0

    function newId() {
        const id = "p_" + _nextId
        _nextId = _nextId + 1
        return id
    }

    function register(plane) {
        if (!plane || !plane.planeId) return
        _planes[plane.planeId] = plane
    }

    function unregister(planeId) {
        if (!planeId) return
        delete _planes[planeId]
        slotsRevision = slotsRevision + 1
    }

    function findById(planeId) {
        return _planes[planeId] || null
    }

    // O(N) scan. Anchors on slotsRevision so binding-tracking works.
    function findAbductor(planeId) {
        const _ = slotsRevision  // dependency anchor
        if (!planeId) return null
        for (const id in _planes) {
            const p = _planes[id]
            if (!p || !p.slots) continue
            for (const s of p.slots) {
                if (s.planeId === planeId) return p
            }
        }
        return null
    }

    function removeFromAllSlots(planeId) {
        if (!planeId) return
        let mutated = false
        for (const id in _planes) {
            const p = _planes[id]
            if (!p || !p.slots || p.slots.length === 0) continue
            const filtered = p.slots.filter(s => s.planeId !== planeId)
            if (filtered.length !== p.slots.length) {
                p.slots = filtered
                mutated = true
            }
        }
        if (mutated) slotsRevision = slotsRevision + 1
    }

    function notifySlotsChanged() {
        slotsRevision = slotsRevision + 1
    }

    // Useful for selection prism: every plane in the scene that has no
    // abductor (top-level) and is window-backed.
    function topLevelPlanes() {
        const _ = slotsRevision
        const out = []
        for (const id in _planes) {
            const p = _planes[id]
            if (!p) continue
            if (findAbductor(p.planeId) === null) out.push(p)
        }
        return out
    }
}
