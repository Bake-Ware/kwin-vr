/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>
    SPDX-FileCopyrightText: 2026 Bake-Ware

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick3D

import org.kde.kwin.vr

/*
 * KwinApplicationWindow — top-level KWin window as a CurvedPlane.
 *
 *   client.vr === true  → top-level (no abductor); free-floating in VR.
 *                         Curvature = intrinsicCurvature (defaultWindowCurvature).
 *   client.vr === false → slot of the pseudomirror for client.output;
 *                         rendered flat, positioned to match frameGeometry.
 *
 * Embeds a KwinTransientWindow as the actual scene-graph rendering
 * child (decorated / thumbnail / thumbnail-xr-item Loader3D + the
 * recursive transient stacks). The plane shell handles registry,
 * abductor, intrinsic state, and decoration visibility.
 */
CurvedPlane {
    id: root

    required property KwinWindowModel windowDataModel
    required property QtObject client
    required property VrFocusControl focusControl
    property real ppu: 20
    property real zOffsetGlobal: 0
    property real normalWindowFlexibleBottom: 0

    // Plane config
    mode: CurvedPlane.Mode.None
    intrinsicSize: client
                   ? Qt.size(client.frameGeometry.width / root.ppu,
                             client.frameGeometry.height / root.ppu)
                   : Qt.size(0, 0)
    intrinsicCurvature: KWinVRConfig.defaultWindowCurvature || 0.0

    // For ray-pick callers that read `grabHandle` to find the pick target.
    readonly property Node grabHandle: root

    // For SpaceAllocator3D.
    readonly property size itemSize: root.intrinsicSize

    // ─── Embedded rendering ───────────────────────────────────────────
    KwinTransientWindow {
        id: rendering
        client: root.client
        ppu: root.ppu
        focusControl: root.focusControl
        windowDataModel: root.windowDataModel
        grabHandle: root.grabHandle
        normalWindowFlexibleBottom: root.normalWindowFlexibleBottom
        zOffsetGlobal: root.zOffsetGlobal
        nextComponent: KwinTransientWindowRecursive {
            ppu: root.ppu
            focusControl: root.focusControl
            nextComponent: rendering.nextComponent
            grabHandle: root.grabHandle
            windowDataModel: root.windowDataModel
            normalWindowFlexibleBottom: KWinVRConfig.minTransientNormalSpacing
        }
    }

    // ─── Abductor switching on client.vr / output / geometry ──────────
    Connections {
        target: root.client
        function onVrChanged() { root._reconcileSlot() }
        function onOutputChanged() { root._reconcileSlot() }
        function onFrameGeometryChanged() { root._updateSlotPosition() }
    }

    function _findPseudoForOutput(output) {
        if (!output || !root.registry) return null
        const tops = root.registry.topLevelPlanes()
        for (const p of tops) {
            if (p._isPseudomirror && p.output === output) return p
        }
        return null
    }

    function _pseudoOverrides(pseudo) {
        const cf = root.client.frameGeometry
        const og = pseudo.output.geometry
        const x = (cf.x + cf.width / 2 - og.x - og.width / 2) / root.ppu
        const y = -(cf.y + cf.height / 2 - og.y - og.height / 2) / root.ppu
        return { position: Qt.vector3d(x, y, 0) }
    }

    function _reconcileSlot() {
        if (!root.registry || !root.client) return
        if (root.client.vr) {
            // Detaching: settle current scene pose into intrinsic so the
            // window stays put visually rather than snapping to origin.
            if (root.topLevelHost) {
                root.intrinsicPosition = root.topLevelHost.mapPositionFromScene(root.scenePosition)
                root.intrinsicRotation = KwinVrHelpers.getRotationDelta(
                    root.topLevelHost.sceneRotation, root.sceneRotation)
            }
            root.registry.removeFromAllSlots(root.planeId)
        } else {
            const pseudo = _findPseudoForOutput(root.client.output)
            if (pseudo) {
                pseudo.addChild(root.planeId, _pseudoOverrides(pseudo))
            }
        }
    }

    function _updateSlotPosition() {
        if (!root.client || root.client.vr) return
        const pseudo = _findPseudoForOutput(root.client.output)
        if (pseudo) {
            pseudo.updateSlotOverrides(root.planeId, _pseudoOverrides(pseudo))
        }
    }

    Component.onCompleted: {
        // CurvedPlane base registered us in registry. Now place ourselves
        // in the right slot list based on current client.vr state.
        Qt.callLater(_reconcileSlot)
    }
}
