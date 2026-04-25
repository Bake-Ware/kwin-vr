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

    // Hide the flat decorated render when the client is in VR state —
    // the CurvedPlane sibling renders the curved thumbnail instead.
    visible: !root.client.minimized && root.client.opacity > 0
             && !root.client.vr
             && (!KwinVrHelpers.screenLocked
                 || client.lockScreen || client.lockScreenOverlay
                 || client.inputMethod)

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
        vrPlane = comp.createObject(topLevelHost, {
            registry: planeRegistry,
            content: root.client,
            ppu: root.ppu,
            intrinsicCurvature: KWinVRConfig.defaultWindowCurvature,
            // Visible only when the client is in VR mode.
            visible: Qt.binding(() => !!(root.client && root.client.vr))
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
