/*
    SPDX-FileCopyrightText: 2026 bake

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick3D

import org.kde.kwin.vr

/*
 * Flat-monitor scene root (M2): the same 3D workspace rendered into a plain
 * View3D — no HMD, no OpenXR, no DRM lease. The camera is a PerspectiveCamera
 * steered by middle-button drag ("look"); everything else — the ray, grabs,
 * snaps, radial menu — is the identical vocabulary via VrWorkspaceScene.
 *
 * Also the substrate for headless CI testing (kwin_wayland --virtual) and
 * the "spectator-2d free camera" role from doc/DESIGN_MULTI_HMD.md.
 */
View3D {
    id: flatView
    anchors.fill: parent

    property KwinVrInputDevice kwinInput
    property KwinVrInputFilter kwinInputFilter

    readonly property VrWorkspaceScene workspace: ws

    environment: SceneEnvironment {
        clearColor: "skyblue"
        backgroundMode: SceneEnvironment.Color
        depthPrePassEnabled: KWinVRConfig.depthPrePassEnabled
        depthTestEnabled: KWinVRConfig.depthTestEnabled
    }

    /* Head stand-in: yaw/pitch rig around a PerspectiveCamera. Middle-drag
       rotates it — the flat equivalent of turning your head, so gaze-coupled
       behaviors (follow mode, gaze reclaim, head scroll) keep working. */
    Node {
        id: headRig
        property real yaw: 0
        property real pitch: 0
        eulerRotation: Qt.vector3d(pitch, yaw, 0)

        PerspectiveCamera {
            id: cam
            clipNear: 1
            clipFar: 100000
            fieldOfView: KWinVRConfig.flatFov
        }
    }
    camera: cam

    function lookBy(dx: real, dy: real) {
        headRig.yaw -= dx * KWinVRConfig.flatLookSensitivity
        headRig.pitch = Math.max(-89, Math.min(89,
            headRig.pitch - dy * KWinVRConfig.flatLookSensitivity))
    }

    VrWorkspaceScene {
        id: ws
        camera: cam
        pickingView: flatView
        kwinInput: flatView.kwinInput
        kwinInputFilter: flatView.kwinInputFilter

        blendSupported: false
    }
}
