/*
    SPDX-FileCopyrightText: 2026 Bake-Ware

    SPDX-License-Identifier: GPL-2.0-or-later
*/

/*
 * PlaneInteractionManager — drives snap / stack / drag dispatch for
 * CurvedPlanes via the existing pickRay grab/release events.
 *
 *   on grab:     mark plane isGrabbed=true, removeFromAllSlots so
 *                pickRay can move it freely.
 *   during grab: scan picks for a candidate target plane; classify by
 *                hit UV (centre = stack, edge = snap row).
 *   on release:  if target → snap or stack commit; else settle in place.
 */

import QtQuick
import QtQuick3D

import org.kde.kwin.vr

QtObject {
    id: root

    // xray + picking wired by the active viewport (XrScene today;
    // Vr2DViewport will route mouse picks). Null until a viewport binds.
    property var xray: null
    property var picking: null
    required property var registry
    required property Node topLevelHost

    property real edgeBand: 0.25

    // 0 = none, 1 = snap (row pack), 2 = stack
    enum Action { None, Snap, Stack }

    property var _grabbedPlane: null
    property var _snapTarget: null
    property int _snapAction: PlaneInteractionManager.Action.None

    // === Helpers ===

    // Walk a hit object up to the owning CurvedPlane via grabHandle.
    function _planeFromObject(obj) {
        if (!obj) return null
        if (obj.planeId !== undefined && obj.registry !== undefined) return obj
        if (obj.grabHandle && obj.grabHandle.planeId !== undefined
            && obj.grabHandle.registry !== undefined) return obj.grabHandle
        let n = obj
        while (n) {
            if (n.planeId !== undefined && n.registry !== undefined) return n
            n = n.parent
        }
        return null
    }

    // Convert hit UV to action.
    function _uvToAction(u, v) {
        const e = root.edgeBand
        if (u < e || u > 1 - e || v < e || v > 1 - e) return PlaneInteractionManager.Action.Snap
        return PlaneInteractionManager.Action.Stack
    }

    // === Grab / release ===

    readonly property Connections _grabWatcher: Connections {
        target: root.xray
        function onGrabbedObjectChanged() {
            const obj = root.xray.grabbedObject
            const plane = root._planeFromObject(obj)
            if (plane) {
                // Grab start. Order matters:
                //   1. Capture the current scene pose into intrinsic so the
                //      plane has a sane fallback position for the brief
                //      moment between detach and Xray taking over.
                //   2. Suspend the position/rotation binding (isGrabbed=true)
                //      BEFORE removing from slots, otherwise the binding
                //      fires once on abductor change and snaps the plane to
                //      its intrinsic origin (which a freshly-spawned screen-
                //      state window has at 0,0,0).
                //   3. Detach.
                root._grabbedPlane = plane
                root._snapTarget = null
                root._snapAction = PlaneInteractionManager.Action.None
                if (plane.topLevelHost) {
                    plane.intrinsicPosition = plane.topLevelHost.mapPositionFromScene(plane.scenePosition)
                    plane.intrinsicRotation = KwinVrHelpers.getRotationDelta(
                        plane.topLevelHost.sceneRotation, plane.sceneRotation)
                }
                plane.isGrabbed = true
                root.registry.removeFromAllSlots(plane.planeId)
                console.log(Logger.kwinvr, "PlaneInteraction grab", plane.planeId)
            } else if (root._grabbedPlane) {
                // Grab end.
                const p = root._grabbedPlane
                const tgt = root._snapTarget
                const act = root._snapAction
                if (tgt && act !== PlaneInteractionManager.Action.None) {
                    root._commit(p, tgt, act)
                } else {
                    // No snap. Settle: capture current scene pose into intrinsic.
                    if (p.topLevelHost) {
                        p.intrinsicPosition = p.topLevelHost.mapPositionFromScene(p.scenePosition)
                        p.intrinsicRotation = KwinVrHelpers.getRotationDelta(
                            p.topLevelHost.sceneRotation, p.sceneRotation)
                    }
                }
                p.isGrabbed = false
                console.log(Logger.kwinvr, "PlaneInteraction release", p.planeId,
                            "target=", tgt ? tgt.planeId : "null", "action=", act)
                root._grabbedPlane = null
                root._snapTarget = null
                root._snapAction = PlaneInteractionManager.Action.None
            }
        }
    }

    // === Hover scan during drag ===

    readonly property Connections _scanWatcher: Connections {
        target: root.picking
        enabled: root._grabbedPlane !== null
        function onLastAllPicksChanged() {
            const picks = root.picking.lastAllPicks
            const grabbed = root._grabbedPlane
            for (const pick of picks) {
                const obj = pick.objectHit
                            ?? root.picking.getHoveredNodeFromItem(pick.itemHit)
                const plane = root._planeFromObject(obj)
                if (!plane) continue
                if (plane === grabbed) continue
                // Don't snap onto something that's already abducted by the
                // grabbed (would be cyclic). Also skip pseudomirrors —
                // dropping on a monitor goes to screen state not snap.
                if (plane._isPseudomirror) continue
                root._snapTarget = plane
                root._snapAction = root._uvToAction(pick.uvPosition.x, pick.uvPosition.y)
                return
            }
            root._snapTarget = null
            root._snapAction = PlaneInteractionManager.Action.None
        }
    }

    // === Commit ===

    function _commit(dropped, target, action) {
        if (!dropped || !target) return
        const ab = target.abductor
        const wantContainerMode = (action === PlaneInteractionManager.Action.Stack)
                                ? CurvedPlane.Mode.Stack : CurvedPlane.Mode.Snap

        if (ab && ab.mode === wantContainerMode) {
            // Existing container of right mode → just add.
            ab.addChild(dropped.planeId)
            return
        }

        // Otherwise wrap target + dropped in a new container.
        const tgtScene = target.scenePosition
        const tgtRot = target.sceneRotation
        const cont = _createContainer(wantContainerMode, tgtScene, tgtRot)
        if (!cont) return
        cont.addChild(target.planeId)
        cont.addChild(dropped.planeId)
    }

    function _createContainer(mode, scenePosition, sceneRotation) {
        const comp = Qt.createComponent("CurvedPlane.qml")
        if (comp.status !== Component.Ready) {
            console.log(Logger.kwinvr,
                        "Container component fail:", comp.errorString())
            return null
        }
        const props = {
            registry: root.registry,
            topLevelHost: root.topLevelHost,
            mode: mode,
            content: null
        }
        if (root.topLevelHost) {
            props.intrinsicPosition = root.topLevelHost.mapPositionFromScene(scenePosition)
            props.intrinsicRotation = KwinVrHelpers.getRotationDelta(
                root.topLevelHost.sceneRotation, sceneRotation)
        }
        return comp.createObject(root.topLevelHost, props)
    }
}
