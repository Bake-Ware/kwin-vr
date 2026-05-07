/*
    SPDX-FileCopyrightText: 2026 Bake-Ware

    SPDX-License-Identifier: GPL-2.0-or-later
*/

/*
 * Vr2DViewport — a Plasma client window that renders the curved-plane
 * scene from a 2D-controlled orbit camera.
 *
 * Use cases:
 *   - Fallback when VR is started but no DRM lease is open (no HMD).
 *   - Future: spectator/inspector window into a live VR session.
 *   - Future: additional viewers when invited into the user's
 *     environment (local-process for now; remote via Telesthete later).
 *
 * Renders the same WindowSceneRoot as XrScene via importScene. Each
 * Vr2DViewport instance has its own camera + input; the scene state is
 * shared. Single-grab is enforced by PlaneInteractionManager.
 */

import QtQuick
import QtQuick.Window
import QtQuick3D
import QtQuick3D.Helpers

import org.kde.kwin.vr

Window {
    id: root

    // Shared scene to render. Must be set by the spawner.
    required property WindowSceneRoot scene

    title: qsTr("KWin-VR Viewport")
    width: 1280
    height: 720
    color: "skyblue"
    visible: true

    View3D {
        id: view3d
        anchors.fill: parent
        importScene: scene
        camera: orbitCam

        environment: SceneEnvironment {
            clearColor: "skyblue"
            backgroundMode: SceneEnvironment.Color
            antialiasingMode: SceneEnvironment.MSAA
            antialiasingQuality: SceneEnvironment.Medium
        }

        // Orbit pivot. Sits at the centre of where the curved-plane
        // grabHandle is in scene-space, so the camera orbits the
        // visible cluster of windows rather than scene origin.
        Node {
            id: orbitOrigin
            position: Qt.vector3d(0, 0, -scene.distance)
        }

        // Camera starts at scene origin facing the cluster — same pose
        // the XR head would have at session start. OrbitCameraController
        // takes over once user drags.
        PerspectiveCamera {
            id: orbitCam
            position: Qt.vector3d(0, 0, 0)
            eulerRotation: Qt.vector3d(0, 0, 0)
            fieldOfView: 60
            clipNear: 0.1
            clipFar: 1000
        }

        DirectionalLight {
            eulerRotation.x: -30
            eulerRotation.y: -45
        }
    }

    // Drag-to-orbit + wheel-to-zoom. Provided by QtQuick3D.Helpers.
    OrbitCameraController {
        anchors.fill: view3d
        camera: orbitCam
        origin: orbitOrigin
    }
}
