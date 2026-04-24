/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick3D

/*
 * WorkSurfaceRegistry — scene-level manager for WorkSurface instances.
 * Lives as a child of XrScene.
 *
 * Phase 1: lifecycle (create/merge/detach/dissolve). Bisection lands
 * in a follow-up commit; for now, removeMember always takes everything
 * left as a single component.
 */
Node {
    id: root

    property int _nextId: 1

    /* Emitted on any surface lifecycle change for debug / telemetry. */
    signal surfaceChanged(string surfaceId, string kind)  // kind: create|merge|join|detach|dissolve

    Component {
        id: surfaceComponent
        WorkSurface {}
    }

    function _newId() {
        return "ws_" + (_nextId++)
    }

    function _createSurface() {
        const s = surfaceComponent.createObject(root, { surfaceId: _newId() })
        console.log(Logger.kwinvr, "WorkSurface create", s.surfaceId)
        surfaceChanged(s.surfaceId, "create")
        return s
    }

    function _assignMember(surface, win, neighbor, edge) {
        if (!surface || !win) return
        const members = surface.members.slice()
        if (members.indexOf(win) === -1) {
            members.push(win)
            surface.members = members
        }
        win.workSurface = surface
        if (neighbor) {
            const adj = Object.assign({}, surface.adjacency)
            const wid = _windowKey(win)
            const nid = _windowKey(neighbor)
            if (!adj[wid]) adj[wid] = []
            if (!adj[nid]) adj[nid] = []
            adj[wid] = adj[wid].concat([{ neighbor: nid, edge: edge }])
            adj[nid] = adj[nid].concat([{ neighbor: wid, edge: _oppositeEdge(edge) }])
            surface.adjacency = adj
        }
    }

    function _windowKey(w) {
        if (!w || !w.client) return ""
        return w.client.internalId || w.client.resourceClass + ":" + (w.client.pid || 0)
    }

    function _oppositeEdge(edge) {
        switch (edge) {
            case "left": return "right"
            case "right": return "left"
            case "above": return "below"
            case "below": return "above"
            case "stack": return "stack"
            default: return ""
        }
    }

    /*
     * Public API — called by WindowSnapManager on snap commit.
     * edge ∈ {"left","right","above","below","stack"} describes the snap
     * relationship from dragged → target (dragged is on the `edge` of target).
     */
    function joinOnSnap(dragged, target, edge) {
        if (!dragged || !target || dragged === target) return null

        const sD = dragged.workSurface
        const sT = target.workSurface

        if (!sD && !sT) {
            const s = _createSurface()
            _assignMember(s, target, null, null)
            _assignMember(s, dragged, target, edge)
            surfaceChanged(s.surfaceId, "join")
            return s
        }
        if (sD && !sT) {
            _assignMember(sD, target, dragged, _oppositeEdge(edge))
            surfaceChanged(sD.surfaceId, "join")
            return sD
        }
        if (!sD && sT) {
            _assignMember(sT, dragged, target, edge)
            surfaceChanged(sT.surfaceId, "join")
            return sT
        }
        if (sD === sT) {
            // Already same surface — update adjacency only.
            const adj = Object.assign({}, sT.adjacency)
            const wid = _windowKey(dragged)
            const nid = _windowKey(target)
            if (!adj[wid]) adj[wid] = []
            if (!adj[nid]) adj[nid] = []
            adj[wid] = adj[wid].concat([{ neighbor: nid, edge: edge }])
            adj[nid] = adj[nid].concat([{ neighbor: wid, edge: _oppositeEdge(edge) }])
            sT.adjacency = adj
            return sT
        }
        // Both in different surfaces — merge sD into sT (target wins).
        for (const m of sD.members) {
            if (sT.members.indexOf(m) === -1) {
                const members = sT.members.slice()
                members.push(m)
                sT.members = members
                m.workSurface = sT
            }
        }
        // Merge adjacency.
        const merged = Object.assign({}, sT.adjacency)
        for (const k in sD.adjacency) {
            merged[k] = (merged[k] || []).concat(sD.adjacency[k])
        }
        // Add the new edge between dragged and target.
        const wid = _windowKey(dragged)
        const nid = _windowKey(target)
        if (!merged[wid]) merged[wid] = []
        if (!merged[nid]) merged[nid] = []
        merged[wid] = merged[wid].concat([{ neighbor: nid, edge: edge }])
        merged[nid] = merged[nid].concat([{ neighbor: wid, edge: _oppositeEdge(edge) }])
        sT.adjacency = merged

        sD.members = []
        sD.adjacency = ({})
        sD.destroy()
        surfaceChanged(sT.surfaceId, "merge")
        return sT
    }

    /*
     * Remove a window from its surface. Phase 1: no bisection — remaining
     * members stay as one component. On drop to 1 member, dissolve.
     */
    function removeMember(win) {
        if (!win || !win.workSurface) return
        const s = win.workSurface
        const members = s.members.slice()
        const idx = members.indexOf(win)
        if (idx !== -1) members.splice(idx, 1)
        s.members = members

        const adj = Object.assign({}, s.adjacency)
        const wid = _windowKey(win)
        // Drop all edges touching `win`.
        delete adj[wid]
        for (const k in adj) {
            adj[k] = adj[k].filter(e => e.neighbor !== wid)
        }
        s.adjacency = adj

        win.workSurface = null
        surfaceChanged(s.surfaceId, "detach")

        if (s.members.length <= 1) {
            _dissolve(s)
        }
    }

    function _dissolve(s) {
        if (!s) return
        // Clear surface ref on any remaining member (the 0- or 1-member case).
        for (const m of s.members.slice()) {
            m.workSurface = null
        }
        console.log(Logger.kwinvr, "WorkSurface dissolve", s.surfaceId)
        surfaceChanged(s.surfaceId, "dissolve")
        s.members = []
        s.adjacency = ({})
        s.destroy()
    }
}
