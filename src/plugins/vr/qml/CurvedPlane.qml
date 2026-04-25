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
 *   - render*  =  intrinsic*  when no abductor;
 *                 abductor.computeChild*(myId)  otherwise.
 *   - Containers (content === null) with ≤ 1 slot dissolve next layout pass.
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

    // === Content (window-backed) ===
    property QtObject content: null   // KWin client OR null for pure container
    property real ppu: 20

    // === Intrinsic state (used when no abductor) ===
    property vector3d intrinsicPosition: Qt.vector3d(0, 0, 0)
    property quaternion intrinsicRotation: Qt.quaternion(1, 0, 0, 0)
    property size intrinsicSize: Qt.size(1, 1)
    property real intrinsicCurvature: 0.0

    // === Children layout ===
    property int mode: CurvedPlane.Mode.None
    // Each slot: { planeId: string, overrides: {position?, rotation?, size?, curvature?} }
    property var slots: []

    // === Effective state (resolved from abductor or intrinsic) ===
    readonly property var abductor: registry ? registry.findAbductor(planeId) : null
    readonly property bool isTopLevel: abductor === null

    readonly property vector3d effectivePosition: {
        if (isTopLevel || !abductor) return intrinsicPosition
        return abductor.computeChildPosition(planeId)
    }
    readonly property quaternion effectiveRotation: {
        if (isTopLevel || !abductor) return intrinsicRotation
        return abductor.computeChildRotation(planeId)
    }
    readonly property size effectiveSize: {
        if (isTopLevel || !abductor) return intrinsicSize
        return abductor.computeChildSize(planeId)
    }
    readonly property real effectiveCurvature: {
        if (isTopLevel || !abductor) return intrinsicCurvature
        return abductor.computeChildCurvature(planeId)
    }

    // === Apply effective transform to the Node ===
    position: effectivePosition
    rotation: effectiveRotation

    // === Layout API ===

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
        if (ovr.position !== undefined) return ovr.position
        switch (mode) {
        case CurvedPlane.Mode.Free:
            return Qt.vector3d(0, 0, 0)
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
        let cumX = 0
        for (let i = 0; i < idx; ++i) {
            const cId = slots[i].planeId
            const sz = computeChildSize(cId)
            cumX += sz.width + gap
        }
        const mySz = computeChildSize(slots[idx].planeId)
        // Centre-anchor each child; container is centred at 0 in its own frame.
        // Total width = sum(sizes) + gaps. Origin at start - we'll shift below.
        let totalW = 0
        for (let i = 0; i < slots.length; ++i) {
            const cId = slots[i].planeId
            totalW += computeChildSize(cId).width
            if (i > 0) totalW += gap
        }
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
        // Only containers (content === null) auto-dissolve.
        if (content !== null) return
        if (slots.length === 0) {
            registry.unregister(planeId)
            root.destroy()
        } else if (slots.length === 1) {
            // Promote lone child to top-level. Cap its pose at current effective.
            const lone = registry.findById(slots[0].planeId)
            if (lone) {
                lone.intrinsicPosition = lone.effectivePosition
                lone.intrinsicRotation = lone.effectiveRotation
            }
            slots = []
            registry.notifySlotsChanged()
            registry.unregister(planeId)
            root.destroy()
        }
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
