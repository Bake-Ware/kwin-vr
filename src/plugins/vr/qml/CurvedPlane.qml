/*
    SPDX-FileCopyrightText: 2026 Bake-Ware

    SPDX-License-Identifier: GPL-2.0-or-later
*/

/*
 * CurvedPlane — the single primitive of the VR scene.
 *
 * Every window, snap group, stack, free container, pseudomirror is a
 * CurvedPlane. Properties drive behaviour, not type checks.
 *
 * Key invariants (architecture.md):
 *   - Plane never reads its abductor; it queries the registry.
 *   - Plane is in at most one container's slots list at a time.
 *   - Top-level (no abductor): render = intrinsic.
 *   - Abducted: render = abductor.computeChild*(myId), in scene frame
 *     converted to topLevelHost-local for the Qt position binding.
 *   - Containers (content === null) with ≤ 1 slot dissolve next layout pass.
 *
 * Qt scene-graph parent: always topLevelHost. We do NOT reparent on
 * abduction — instead we compute scene poses from abductor and convert
 * to topLevelHost-local. This keeps drag/grab clean (pickRay's imperative
 * writes don't fight an abductor reparent).
 */

import QtQuick
import QtQuick3D

import org.kde.kwin.vr

Node {
    id: root

    enum Mode {
        None,   // leaf, no children
        Free,   // children at arbitrary positions on me
        Snap,   // 1D row pack with magnetise
        Stack   // cascade
    }

    // === Identity ===
    property string planeId: ""
    property var registry: null

    // === Scene host (Qt parent) ===
    property Node topLevelHost: null

    // === Content ===
    property QtObject content: null
    property real ppu: 20

    // === Intrinsic (used when no abductor; in topLevelHost frame) ===
    property vector3d intrinsicPosition: Qt.vector3d(0, 0, 0)
    property quaternion intrinsicRotation: Qt.quaternion(1, 0, 0, 0)
    property size intrinsicSize: Qt.size(1, 1)
    property real intrinsicCurvature: 0.0

    // === Children layout ===
    property int mode: CurvedPlane.Mode.None
    property var slots: []

    // When true, Free-mode children get a compounding z lift of
    // (slotIndex+1) * KWinVRConfig.zWindowMarginTop on top of any
    // override.position so overlapping windows float forward of each
    // other and the host plane. Pseudomirrors enable this; user-created
    // free containers don't.
    property bool stackChildren: false

    // === Grab override ===
    // Set by the interaction manager during a grab. Suspends the
    // position/rotation bindings so pickRay can write imperatively.
    property bool isGrabbed: false

    // Pseudomirror flag — set by KwinPseudoOutputMirror migration; lets
    // its hosted children know to suppress their own control tab.
    property bool _isPseudomirror: false

    // === Effective state ===
    readonly property var abductor: registry ? registry.findAbductor(planeId) : null
    readonly property bool isTopLevel: abductor === null

    readonly property vector3d _abductorLocalPosition: {
        return abductor ? abductor.computeChildPosition(planeId) : Qt.vector3d(0, 0, 0)
    }
    readonly property quaternion _abductorLocalRotation: {
        return abductor ? abductor.computeChildRotation(planeId) : Qt.quaternion(1, 0, 0, 0)
    }

    readonly property vector3d _targetScenePosition: {
        if (!abductor) {
            return topLevelHost ? topLevelHost.mapPositionToScene(intrinsicPosition)
                                : intrinsicPosition
        }
        return abductor.mapPositionToScene(_abductorLocalPosition)
    }
    readonly property vector3d _targetLocalPosition: {
        return topLevelHost ? topLevelHost.mapPositionFromScene(_targetScenePosition)
                            : _targetScenePosition
    }

    // For rotation: scene-target = abductor.sceneRotation * localInAb,
    // then convert to topLevelHost-local via getRotationDelta.
    readonly property quaternion _targetLocalRotation: {
        let sceneRot
        if (!abductor) {
            sceneRot = topLevelHost
                       ? topLevelHost.sceneRotation.times(intrinsicRotation)
                       : intrinsicRotation
        } else {
            sceneRot = abductor.sceneRotation.times(_abductorLocalRotation)
        }
        return topLevelHost
               ? KwinVrHelpers.getRotationDelta(topLevelHost.sceneRotation, sceneRot)
               : sceneRot
    }

    // Apply via Binding so isGrabbed can suspend.
    Binding {
        target: root
        property: "position"
        value: root._targetLocalPosition
        when: !root.isGrabbed
        restoreMode: Binding.RestoreNone
    }
    Binding {
        target: root
        property: "rotation"
        value: root._targetLocalRotation
        when: !root.isGrabbed
        restoreMode: Binding.RestoreNone
    }

    readonly property size effectiveSize: {
        if (isTopLevel || !abductor) return intrinsicSize
        return abductor.computeChildSize(planeId)
    }
    readonly property real effectiveCurvature: {
        if (isTopLevel || !abductor) return intrinsicCurvature
        return abductor.computeChildCurvature(planeId)
    }

    // === Layout API (called by children's effective* bindings) ===

    function _slotIndexOf(childId) {
        for (let i = 0; i < slots.length; ++i) {
            if (slots[i].planeId === childId) return i
        }
        return -1
    }

    function computeChildPosition(childId) {
        const i = _slotIndexOf(childId)
        if (i < 0) return Qt.vector3d(0, 0, 0)
        const slot = slots[i]
        const ovr = slot.overrides || ({})
        // Pseudomirror's local +Z points away from the camera (into the
        // bezel), so we negate to push children forward (toward the user).
        const stackZ = (mode === CurvedPlane.Mode.Free && stackChildren)
                       ? -(i + 1) * (KWinVRConfig.zWindowMarginTop || 1.0)
                       : 0
        if (ovr.position !== undefined) {
            return Qt.vector3d(ovr.position.x, ovr.position.y,
                               ovr.position.z + stackZ)
        }
        switch (mode) {
        case CurvedPlane.Mode.Free:
            return Qt.vector3d(0, 0, stackZ)
        case CurvedPlane.Mode.Snap:
            return _snapPosition(i)
        case CurvedPlane.Mode.Stack:
            return _stackPosition(i)
        }
        return Qt.vector3d(0, 0, 0)
    }

    function computeChildRotation(childId) {
        const i = _slotIndexOf(childId)
        if (i < 0) return Qt.quaternion(1, 0, 0, 0)
        const slot = slots[i]
        const ovr = slot.overrides || ({})
        if (ovr.rotation !== undefined) return ovr.rotation
        return Qt.quaternion(1, 0, 0, 0)
    }

    function computeChildSize(childId) {
        const i = _slotIndexOf(childId)
        if (i < 0) return Qt.size(1, 1)
        const slot = slots[i]
        const ovr = slot.overrides || ({})
        if (ovr.size !== undefined) return ovr.size
        const child = registry ? registry.findById(childId) : null
        return child ? child.intrinsicSize : Qt.size(1, 1)
    }

    function computeChildCurvature(childId) {
        const i = _slotIndexOf(childId)
        if (i < 0) return intrinsicCurvature
        const slot = slots[i]
        const ovr = slot.overrides || ({})
        if (ovr.curvature !== undefined) return ovr.curvature
        return intrinsicCurvature
    }

    function _snapPosition(idx) {
        const gap = KWinVRConfig.snapGap || 0.02
        let totalW = 0
        for (let i = 0; i < slots.length; ++i) {
            const cId = slots[i].planeId
            totalW += computeChildSize(cId).width
            if (i > 0) totalW += gap
        }
        let cumX = 0
        for (let i = 0; i < idx; ++i) {
            const cId = slots[i].planeId
            cumX += computeChildSize(cId).width + gap
        }
        const mySz = computeChildSize(slots[idx].planeId)
        const x = cumX + mySz.width / 2 - totalW / 2
        return Qt.vector3d(x, 0, 0)
    }

    function _stackPosition(idx) {
        const step = KWinVRConfig.zSurfaceMarginTop || 0.01
        return Qt.vector3d(step * idx, -step * idx, step * idx)
    }

    // === Slot mutation ===

    function addChild(childPlaneId, overrides, insertAt) {
        if (!registry || !childPlaneId) return
        registry.removeFromAllSlots(childPlaneId)
        const newSlot = { planeId: childPlaneId, overrides: overrides || ({}) }
        const newSlots = slots.slice()
        if (insertAt !== undefined && insertAt !== null
            && insertAt >= 0 && insertAt <= newSlots.length) {
            newSlots.splice(insertAt, 0, newSlot)
        } else {
            newSlots.push(newSlot)
        }
        slots = newSlots
        registry.notifySlotsChanged()
    }

    function removeChild(childPlaneId) {
        if (!registry) return
        const before = slots.length
        const newSlots = slots.filter(s => s.planeId !== childPlaneId)
        if (newSlots.length === before) return
        slots = newSlots
        registry.notifySlotsChanged()
        Qt.callLater(_maybeDissolve)
    }

    function updateSlotOverrides(childId, newOverrides) {
        if (!registry) return
        const newSlots = slots.map(s => {
            if (s.planeId !== childId) return s
            return { planeId: s.planeId,
                     overrides: Object.assign({}, s.overrides || ({}), newOverrides) }
        })
        slots = newSlots
        registry.notifySlotsChanged()
    }

    function _maybeDissolve() {
        if (content !== null) return
        if (slots.length === 0) {
            registry.unregister(planeId)
            root.destroy()
        } else if (slots.length === 1) {
            const lone = registry.findById(slots[0].planeId)
            if (lone) {
                // Settle lone child at its current scene pose.
                const sp = lone.scenePosition
                const sr = lone.sceneRotation
                if (lone.topLevelHost) {
                    lone.intrinsicPosition = lone.topLevelHost.mapPositionFromScene(sp)
                    lone.intrinsicRotation = KwinVrHelpers.getRotationDelta(
                        lone.topLevelHost.sceneRotation, sr)
                }
            }
            slots = []
            registry.notifySlotsChanged()
            registry.unregister(planeId)
            root.destroy()
        }
    }

    // === Render: window content (if any) ===
    Loader3D {
        active: root.content !== null
        sourceComponent: CurvedWindowContent {
            client: root.content
            grabHandle: root
            sizeWorld: root.effectiveSize
            curvature: root.effectiveCurvature
        }
    }

    // === Decoration: control tab ===
    Loader3D {
        active: !root._suppressControlTab
        sourceComponent: PlaneControlTab {
            plane: root
            onDissolveRequested: {
                if (root.content !== null) return
                if (root.registry) {
                    for (const s of root.slots) {
                        const ch = root.registry.findById(s.planeId)
                        if (ch && ch.topLevelHost) {
                            ch.intrinsicPosition = ch.topLevelHost.mapPositionFromScene(ch.scenePosition)
                            ch.intrinsicRotation = KwinVrHelpers.getRotationDelta(
                                ch.topLevelHost.sceneRotation, ch.sceneRotation)
                        }
                    }
                    root.slots = []
                    root.registry.notifySlotsChanged()
                    root.registry.unregister(root.planeId)
                }
                root.destroy()
            }
            onCurvatureNudge: (direction) => {
                const step = (KWinVRConfig.curvatureScrollStep || 0.1) * direction
                const ab = root.abductor
                if (ab) {
                    const cur = root.effectiveCurvature
                    const next = Math.max(0, Math.min(6, cur + step))
                    ab.updateSlotOverrides(root.planeId, { curvature: next })
                } else {
                    root.intrinsicCurvature = Math.max(0, Math.min(6,
                        root.intrinsicCurvature + step))
                }
            }
        }
    }

    readonly property bool _suppressControlTab: {
        if (!abductor) return false
        return abductor._isPseudomirror === true
    }

    // === Lifecycle ===

    Component.onCompleted: {
        if (registry) {
            if (!planeId) planeId = registry.newId()
            registry.register(root)
        }
    }

    Component.onDestruction: {
        if (registry) registry.unregister(planeId)
    }
}
