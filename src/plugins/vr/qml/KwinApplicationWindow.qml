/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick3D

import org.kde.kwin.vr

/* The Application Window contains one non transient window and
 * all its transient windows (menus, popups, other normal windows)
 * arranged as a stack of 3D rectangles.
 *
 * VR vs screen: this Node continues to be the parent for the flat
 * decorated render path (state-machine-driven in XrScene). When the
 * client is in VR state, the flat render hides; a sibling CurvedPlane
 * (created in Component.onCompleted under topLevelHost) takes over.
 */
KwinTransientWindow {
    id: root
    grabHandle: root
    nextComponent: KwinTransientWindowRecursive {
        ppu: root.ppu
        focusControl: root.focusControl
        nextComponent: root.nextComponent
        grabHandle: root.grabHandle
        windowDataModel:  root.windowDataModel
        normalWindowFlexibleBottom: KWinVRConfig.minTransientNormalSpacing
    }

    // The flat decorated render is suppressed entirely — the CurvedPlane
    // sibling (created below) handles rendering for both VR and screen
    // states (when abducted by a pseudomirror plane).
    visible: false

    // Injected from XrScene: registry + the Node under which the
    // VR-state CurvedPlane should be parented (kept independent of
    // this Node's state-machine parent flips).
    property var planeRegistry: null
    property Node topLevelHost: null

    // Reference to the spawned CurvedPlane. Snap/stack/drag operate
    // on this object via the registry.
    property var vrPlane: null

    Component.onCompleted: {
        if (!planeRegistry || !topLevelHost || !root.client) return
        const comp = Qt.createComponent("CurvedPlane.qml")
        if (comp.status !== Component.Ready) {
            console.log(Logger.kwinvr,
                        "CurvedPlane component load failed:", comp.errorString())
            return
        }

        // Spread initial positions across a 3×N grid so multiple VR
        // windows don't all spawn at origin. Index = registry order at
        // construction time (rough heuristic, fine for first round).
        const order = Object.keys(planeRegistry._planes).length
        const cols = 3
        const col = order % cols
        const row = Math.floor(order / cols)
        const initialPos = Qt.vector3d((col - 1) * 1.5, -(row - 0.5) * 1.0, 0)

        vrPlane = comp.createObject(topLevelHost, {
            registry: planeRegistry,
            topLevelHost: topLevelHost,
            content: root.client,
            ppu: root.ppu,
            intrinsicCurvature: KWinVRConfig.defaultWindowCurvature,
            intrinsicPosition: initialPos,
            visible: Qt.binding(() => !!(root.client && !root.client.minimized
                                          && root.client.opacity > 0))
        })
        // Bind intrinsicSize to current frame geometry.
        vrPlane.intrinsicSize = Qt.binding(() => {
            const fg = root.client && root.client.frameGeometry
            if (!fg || fg.width <= 0 || fg.height <= 0) return Qt.size(1, 1)
            return Qt.size(fg.width / root.ppu, fg.height / root.ppu)
        })
    }

    Component.onDestruction: {
        if (vrPlane) {
            vrPlane.destroy()
            vrPlane = null
        }
    }
}
